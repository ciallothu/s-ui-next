package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/alireza0/s-ui/database"
	"github.com/alireza0/s-ui/database/model"
	"github.com/alireza0/s-ui/util/common"
	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"golang.org/x/oauth2"
)

type AuthService struct {
	SettingService
	UserService
}

type oidcPending struct {
	Nonce    string
	Verifier string
	Expiry   time.Time
}

type passkeyPending struct {
	Username string
	Data     *webauthn.SessionData
	Expiry   time.Time
}

var (
	oidcPendingStates      sync.Map
	passkeyPendingSessions sync.Map
)

type OIDCStart struct {
	URL string `json:"url"`
}

func splitSetting(value string) []string {
	fields := strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == '\n' || r == ' ' })
	result := make([]string, 0, len(fields))
	for _, field := range fields {
		if value := strings.TrimSpace(field); value != "" {
			result = append(result, value)
		}
	}
	return result
}

func (s *AuthService) PublicAuthMethods() map[string]interface{} {
	oidcEnabled, _ := s.GetOIDCEnabled()
	passkeyEnabled, _ := s.GetPasskeyEnabled()
	return map[string]interface{}{"oidc": oidcEnabled, "passkey": passkeyEnabled, "totp": true}
}

func (s *AuthService) oidcConfig(ctx context.Context) (*oidc.Provider, *oauth2.Config, error) {
	enabled, _ := s.GetOIDCEnabled()
	if !enabled {
		return nil, nil, common.NewError("OIDC is disabled")
	}
	issuer, _ := s.GetAuthSetting("oidcIssuer")
	clientID, _ := s.GetAuthSetting("oidcClientId")
	clientSecret, _ := s.GetAuthSetting("oidcClientSecret")
	redirectURL, _ := s.GetAuthSetting("oidcRedirectUrl")
	if issuer == "" || clientID == "" || redirectURL == "" {
		return nil, nil, common.NewError("OIDC issuer, client ID and redirect URL are required")
	}
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, nil, err
	}
	scopes, _ := s.GetAuthSetting("oidcScopes")
	parsedScopes := splitSetting(scopes)
	if len(parsedScopes) == 0 {
		parsedScopes = []string{oidc.ScopeOpenID, "profile", "email"}
	}
	if !containsString(parsedScopes, oidc.ScopeOpenID) {
		parsedScopes = append([]string{oidc.ScopeOpenID}, parsedScopes...)
	}
	return provider, &oauth2.Config{ClientID: clientID, ClientSecret: clientSecret, RedirectURL: redirectURL, Endpoint: provider.Endpoint(), Scopes: parsedScopes}, nil
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func (s *AuthService) BeginOIDC(ctx context.Context) (*OIDCStart, error) {
	_, config, err := s.oidcConfig(ctx)
	if err != nil {
		return nil, err
	}
	state, nonce, verifier := common.Random(40), common.Random(40), oauth2.GenerateVerifier()
	now := time.Now()
	oidcPendingStates.Range(func(key, value interface{}) bool {
		if pending, ok := value.(oidcPending); ok && now.After(pending.Expiry) {
			oidcPendingStates.Delete(key)
		}
		return true
	})
	oidcPendingStates.Store(state, oidcPending{Nonce: nonce, Verifier: verifier, Expiry: time.Now().Add(10 * time.Minute)})
	url := config.AuthCodeURL(state, oidc.Nonce(nonce), oauth2.S256ChallengeOption(verifier))
	return &OIDCStart{URL: url}, nil
}

func (s *AuthService) FinishOIDC(ctx context.Context, state, code string) (string, error) {
	raw, ok := oidcPendingStates.LoadAndDelete(state)
	if !ok {
		return "", common.NewError("invalid or expired OIDC state")
	}
	pending := raw.(oidcPending)
	if time.Now().After(pending.Expiry) {
		return "", common.NewError("OIDC state expired")
	}
	provider, config, err := s.oidcConfig(ctx)
	if err != nil {
		return "", err
	}
	token, err := config.Exchange(ctx, code, oauth2.VerifierOption(pending.Verifier))
	if err != nil {
		return "", err
	}
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok {
		return "", common.NewError("OIDC provider did not return an ID token")
	}
	idToken, err := provider.Verifier(&oidc.Config{ClientID: config.ClientID}).Verify(ctx, rawIDToken)
	if err != nil {
		return "", err
	}
	if idToken.Nonce != pending.Nonce {
		return "", common.NewError("invalid OIDC nonce")
	}
	claims := map[string]interface{}{}
	if err := idToken.Claims(&claims); err != nil {
		return "", err
	}
	claimName, _ := s.GetAuthSetting("oidcUsernameClaim")
	if claimName == "" {
		claimName = "preferred_username"
	}
	identity := strings.TrimSpace(toString(claims[claimName]))
	if identity == "" {
		identity = strings.TrimSpace(toString(claims["email"]))
	}
	if identity == "" {
		identity = strings.TrimSpace(toString(claims["sub"]))
	}
	if identity == "" {
		return "", common.NewError("OIDC identity claim is empty")
	}
	var user model.User
	db := database.GetDB()
	if err := db.Where("username = ?", identity).First(&user).Error; err == nil {
		return user.Username, nil
	}
	allowedSetting, _ := s.GetAuthSetting("oidcAllowedUsers")
	allowed := splitSetting(strings.ToLower(allowedSetting))
	if !containsString(allowed, strings.ToLower(identity)) {
		return "", common.NewError("OIDC identity is not allowed")
	}
	if err := db.First(&user).Error; err != nil {
		return "", err
	}
	return user.Username, nil
}

func toString(value interface{}) string {
	if text, ok := value.(string); ok {
		return text
	}
	return ""
}

type authWebUser struct {
	User        model.User
	Credentials []webauthn.Credential
}

func (u *authWebUser) WebAuthnID() []byte {
	value := sha256.Sum256([]byte("s-ui-passkey-user:" + u.User.Username))
	return value[:]
}
func (u *authWebUser) WebAuthnName() string                       { return u.User.Username }
func (u *authWebUser) WebAuthnDisplayName() string                { return u.User.Username }
func (u *authWebUser) WebAuthnCredentials() []webauthn.Credential { return u.Credentials }

func (s *AuthService) webAuthn() (*webauthn.WebAuthn, error) {
	enabled, _ := s.GetPasskeyEnabled()
	if !enabled {
		return nil, common.NewError("passkeys are disabled")
	}
	rpID, _ := s.GetAuthSetting("passkeyRpId")
	originsRaw, _ := s.GetAuthSetting("passkeyOrigins")
	origins := splitSetting(originsRaw)
	if rpID == "" || len(origins) == 0 {
		return nil, common.NewError("passkey RP ID and origins are required")
	}
	return webauthn.New(&webauthn.Config{
		RPDisplayName: "S-UI", RPID: rpID, RPOrigins: origins,
		AuthenticatorSelection: protocol.AuthenticatorSelection{ResidentKey: protocol.ResidentKeyRequirementPreferred, UserVerification: protocol.VerificationRequired},
	})
}

func (s *AuthService) loadWebUser(username string) (*authWebUser, error) {
	var user model.User
	if err := database.GetDB().Where("username = ?", username).First(&user).Error; err != nil {
		return nil, err
	}
	var rows []model.PasskeyCredential
	if err := database.GetDB().Where("user_id = ?", user.Id).Find(&rows).Error; err != nil {
		return nil, err
	}
	credentials := make([]webauthn.Credential, 0, len(rows))
	for _, row := range rows {
		var credential webauthn.Credential
		if json.Unmarshal(row.Credential, &credential) == nil {
			credentials = append(credentials, credential)
		}
	}
	return &authWebUser{User: user, Credentials: credentials}, nil
}

func storePasskeySession(username string, data *webauthn.SessionData) string {
	now := time.Now()
	passkeyPendingSessions.Range(func(key, value interface{}) bool {
		if pending, ok := value.(passkeyPending); ok && now.After(pending.Expiry) {
			passkeyPendingSessions.Delete(key)
		}
		return true
	})
	id := common.Random(48)
	passkeyPendingSessions.Store(id, passkeyPending{Username: username, Data: data, Expiry: time.Now().Add(5 * time.Minute)})
	return id
}

func takePasskeySession(id string) (passkeyPending, error) {
	raw, ok := passkeyPendingSessions.LoadAndDelete(id)
	if !ok {
		return passkeyPending{}, common.NewError("passkey ceremony expired")
	}
	pending := raw.(passkeyPending)
	if time.Now().After(pending.Expiry) {
		return passkeyPending{}, common.NewError("passkey ceremony expired")
	}
	return pending, nil
}

func (s *AuthService) BeginPasskeyRegistration(username string) (interface{}, string, error) {
	w, err := s.webAuthn()
	if err != nil {
		return nil, "", err
	}
	user, err := s.loadWebUser(username)
	if err != nil {
		return nil, "", err
	}
	creation, data, err := w.BeginRegistration(user)
	if err != nil {
		return nil, "", err
	}
	return creation, storePasskeySession(username, data), nil
}

func (s *AuthService) FinishPasskeyRegistration(username, sessionID, name string, request *http.Request) error {
	pending, err := takePasskeySession(sessionID)
	if err != nil {
		return err
	}
	if pending.Username != username {
		return common.NewError("passkey user mismatch")
	}
	w, err := s.webAuthn()
	if err != nil {
		return err
	}
	user, err := s.loadWebUser(username)
	if err != nil {
		return err
	}
	credential, err := w.FinishRegistration(user, *pending.Data, request)
	if err != nil {
		return err
	}
	encoded, err := json.Marshal(credential)
	if err != nil {
		return err
	}
	if strings.TrimSpace(name) == "" {
		name = "Passkey"
	}
	return database.GetDB().Create(&model.PasskeyCredential{UserId: user.User.Id, Name: name, Credential: encoded, CreatedAt: time.Now().Unix()}).Error
}

func (s *AuthService) BeginPasskeyLogin(username string) (interface{}, string, error) {
	w, err := s.webAuthn()
	if err != nil {
		return nil, "", err
	}
	user, err := s.loadWebUser(username)
	if err != nil {
		return nil, "", err
	}
	if len(user.Credentials) == 0 {
		return nil, "", common.NewError("no passkey registered for this user")
	}
	assertion, data, err := w.BeginLogin(user)
	if err != nil {
		return nil, "", err
	}
	return assertion, storePasskeySession(username, data), nil
}

func (s *AuthService) FinishPasskeyLogin(sessionID string, request *http.Request) (string, error) {
	pending, err := takePasskeySession(sessionID)
	if err != nil {
		return "", err
	}
	w, err := s.webAuthn()
	if err != nil {
		return "", err
	}
	user, err := s.loadWebUser(pending.Username)
	if err != nil {
		return "", err
	}
	credential, err := w.FinishLogin(user, *pending.Data, request)
	if err != nil {
		return "", err
	}
	encoded, _ := json.Marshal(credential)
	var rows []model.PasskeyCredential
	if err := database.GetDB().Where("user_id = ?", user.User.Id).Find(&rows).Error; err != nil {
		return "", err
	}
	for _, row := range rows {
		var saved webauthn.Credential
		if json.Unmarshal(row.Credential, &saved) == nil && bytes.Equal(saved.ID, credential.ID) {
			if err := database.GetDB().Model(&row).Updates(map[string]interface{}{"credential": encoded, "last_used_at": time.Now().Unix()}).Error; err != nil {
				return "", err
			}
			return pending.Username, nil
		}
	}
	return "", common.NewError("passkey credential not found")
}

func (s *AuthService) ListPasskeys(username string) ([]model.PasskeyCredential, error) {
	var rows []model.PasskeyCredential
	err := database.GetDB().Where("user_id = (SELECT id FROM users WHERE username = ?)", username).Order("id asc").Find(&rows).Error
	return rows, err
}

func (s *AuthService) DeletePasskey(username, id string) error {
	return database.GetDB().Where("id = ? AND user_id = (SELECT id FROM users WHERE username = ?)", id, username).Delete(&model.PasskeyCredential{}).Error
}

func (s *AuthService) SecuritySummary(username string) (map[string]interface{}, error) {
	var user model.User
	if err := database.GetDB().Where("username = ?", username).First(&user).Error; err != nil {
		return nil, err
	}
	passkeys, err := s.ListPasskeys(username)
	if err != nil {
		return nil, err
	}
	sort.Slice(passkeys, func(i, j int) bool { return passkeys[i].Id < passkeys[j].Id })
	return map[string]interface{}{"totpEnabled": user.TOTPEnabled, "passkeys": passkeys, "methods": s.PublicAuthMethods()}, nil
}
