package service

import (
	"encoding/json"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/ciallothu/s-ui-next/core"
	"github.com/ciallothu/s-ui-next/database"
	"github.com/ciallothu/s-ui-next/database/model"
	"github.com/ciallothu/s-ui-next/logger"
	"github.com/ciallothu/s-ui-next/util/common"

	"gorm.io/gorm"
)

var (
	LastUpdate          int64
	corePtr             *core.Core
	startCoreMu         sync.Mutex
	startCoreInProgress bool
	lastStartFailTime   time.Time
	startCooldown       = 15 * time.Second
)

type ConfigService struct {
	ClientService
	TlsService
	SettingService
	InboundService
	OutboundService
	ServicesService
	EndpointService
}

type SingBoxConfig struct {
	Log          json.RawMessage   `json:"log"`
	Dns          json.RawMessage   `json:"dns"`
	Ntp          json.RawMessage   `json:"ntp"`
	Inbounds     []json.RawMessage `json:"inbounds"`
	Outbounds    []json.RawMessage `json:"outbounds"`
	Services     []json.RawMessage `json:"services"`
	Endpoints    []json.RawMessage `json:"endpoints"`
	Route        json.RawMessage   `json:"route"`
	Experimental json.RawMessage   `json:"experimental"`
}

func NewConfigService(core *core.Core) *ConfigService {
	corePtr = core
	return &ConfigService{}
}

func (s *ConfigService) GetConfig(data string) (*[]byte, error) {
	return s.getConfigWithDB(database.GetDB(), data)
}

func (s *ConfigService) getConfigWithDB(db *gorm.DB, data string) (*[]byte, error) {
	var err error
	if len(data) == 0 {
		err = db.Model(&model.Setting{}).Select("value").Where("key = ?", "config").First(&data).Error
		if database.IsNotFound(err) {
			data = defaultConfig
			err = nil
		}
		if err != nil {
			return nil, err
		}
	}
	singboxConfig := SingBoxConfig{}
	err = json.Unmarshal([]byte(data), &singboxConfig)
	if err != nil {
		return nil, err
	}

	singboxConfig.Inbounds, err = s.InboundService.GetAllConfig(db)
	if err != nil {
		return nil, err
	}
	singboxConfig.Outbounds, err = s.OutboundService.GetAllConfig(db)
	if err != nil {
		return nil, err
	}
	singboxConfig.Services, err = s.ServicesService.GetAllConfig(db)
	if err != nil {
		return nil, err
	}
	singboxConfig.Endpoints, err = s.EndpointService.GetAllConfig(db)
	if err != nil {
		return nil, err
	}
	singboxConfig.Route, err = injectManagedRoutes(db, singboxConfig.Route)
	if err != nil {
		return nil, err
	}
	rawConfig, err := json.MarshalIndent(singboxConfig, "", "  ")
	if err != nil {
		return nil, err
	}
	return &rawConfig, nil
}

func (s *ConfigService) StartCore() error {
	if corePtr.IsRunning() {
		return nil
	}
	startCoreMu.Lock()
	if startCoreInProgress {
		startCoreMu.Unlock()
		return nil
	}
	if time.Since(lastStartFailTime) < startCooldown {
		logger.Info("start core cooldown ", startCooldown/time.Second, " seconds")
		startCoreMu.Unlock()
		return nil
	}
	startCoreInProgress = true
	startCoreMu.Unlock()
	defer func() {
		startCoreMu.Lock()
		startCoreInProgress = false
		startCoreMu.Unlock()
	}()

	logger.Info("starting core")
	rawConfig, err := s.GetConfig("")
	if err != nil {
		return err
	}
	err = corePtr.Start(*rawConfig)
	if err != nil {
		startCoreMu.Lock()
		lastStartFailTime = time.Now()
		startCoreMu.Unlock()
		logger.Error("start sing-box err:", err.Error())
		return err
	}
	logger.Info("sing-box started")
	return nil
}

func (s *ConfigService) RestartCore() error {
	err := s.StopCore()
	if err != nil {
		return err
	}
	return s.StartCore()
}

func (s *ConfigService) restartCoreWithRaw(config []byte) error {
	startCoreMu.Lock()
	if startCoreInProgress {
		startCoreMu.Unlock()
		return common.NewError("sing-box configuration is already being applied")
	}
	startCoreInProgress = true
	startCoreMu.Unlock()
	defer func() {
		startCoreMu.Lock()
		startCoreInProgress = false
		startCoreMu.Unlock()
	}()
	if corePtr.IsRunning() {
		if err := corePtr.Stop(); err != nil {
			return err
		}
	}
	if err := corePtr.Start(config); err != nil {
		return err
	}
	if !corePtr.IsRunning() {
		return common.NewError("sing-box did not report a running state after apply")
	}
	return nil
}

func (s *ConfigService) restartCoreWithConfig(config json.RawMessage) error {
	startCoreMu.Lock()
	if startCoreInProgress {
		startCoreMu.Unlock()
		return nil
	}
	startCoreInProgress = true
	startCoreMu.Unlock()
	defer func() {
		startCoreMu.Lock()
		startCoreInProgress = false
		startCoreMu.Unlock()
	}()

	if corePtr.IsRunning() {
		if err := corePtr.Stop(); err != nil {
			logger.Error("restart sing-box err (stop):", err.Error())
			return err
		}
	}
	rawConfig, err := s.GetConfig(string(config))
	if err != nil {
		logger.Error("restart sing-box err (get config):", err.Error())
		return err
	}
	if err := corePtr.Start(*rawConfig); err != nil {
		logger.Error("restart sing-box err (start):", err.Error())
		return err
	}
	logger.Info("sing-box restarted with new config")
	return nil
}

func (s *ConfigService) StopCore() error {
	err := corePtr.Stop()
	if err != nil {
		return err
	}
	logger.Info("sing-box stopped")
	return nil
}

func (s *ConfigService) CheckOutbound(tag string, link string) core.CheckOutboundResult {
	if tag == "" {
		return core.CheckOutboundResult{Error: "missing query parameter: tag"}
	}
	if corePtr == nil || !corePtr.IsRunning() {
		return core.CheckOutboundResult{Error: "core not running"}
	}
	return core.CheckOutbound(corePtr.GetCtx(), tag, link)
}

func (s *ConfigService) Save(obj string, act string, data json.RawMessage, initUsers string, loginUser string, hostname string) ([]string, error) {
	return s.SaveWithApply(obj, act, data, initUsers, loginUser, hostname, true)
}

func (s *ConfigService) SaveWithApply(obj string, act string, data json.RawMessage, initUsers string, loginUser string, hostname string, apply bool) ([]string, error) {
	if obj == "endpoints" {
		return s.saveEndpointWithApply(act, data, loginUser, apply)
	}
	var err error
	var objs []string = []string{obj}

	db := database.GetDB()
	tx := db.Begin()
	defer func() {
		if err == nil {
			tx.Commit()
			// Try to start core if it is not running
			if !corePtr.IsRunning() {
				s.StartCore()
			}
		} else {
			tx.Rollback()
		}
	}()

	switch obj {
	case "clients":
		var inboundIds []uint
		inboundIds, err = s.ClientService.Save(tx, act, data, hostname)
		if err == nil && len(inboundIds) > 0 {
			objs = append(objs, "inbounds")
			err = s.InboundService.RestartInbounds(tx, inboundIds)
			if err != nil {
				return nil, common.NewErrorf("failed to update users for inbounds: %v", err)
			}
		}
	case "tls":
		err = s.TlsService.Save(tx, act, data, hostname)
		objs = append(objs, "clients", "inbounds")
	case "inbounds":
		err = s.InboundService.Save(tx, act, data, initUsers, hostname)
		objs = append(objs, "clients")
	case "outbounds":
		err = s.OutboundService.Save(tx, act, data)
	case "services":
		err = s.ServicesService.Save(tx, act, data)
	case "config":
		err = s.SettingService.SaveConfig(tx, data)
		if err != nil {
			return nil, err
		}
		configData := make(json.RawMessage, len(data))
		copy(configData, data)
		go func() { _ = s.restartCoreWithConfig(configData) }()
	case "settings":
		err = s.SettingService.Save(tx, data)
	default:
		return nil, common.NewError("unknown object: ", obj)
	}
	if err != nil {
		return nil, err
	}

	dt := time.Now().Unix()
	err = tx.Create(&model.Changes{
		DateTime: dt,
		Actor:    loginUser,
		Key:      obj,
		Action:   act,
		Obj:      redactChangeData(data),
	}).Error
	if err != nil {
		return nil, err
	}

	LastUpdate = time.Now().Unix()

	return objs, nil
}

func (s *ConfigService) saveEndpointWithApply(act string, data json.RawMessage, loginUser string, apply bool) ([]string, error) {
	oldConfig, oldConfigErr := s.GetConfig("")
	if oldConfigErr != nil {
		return nil, oldConfigErr
	}
	tx := database.GetDB().Begin()
	if tx.Error != nil {
		return nil, tx.Error
	}
	rollback := func() { _ = tx.Rollback().Error }
	if err := s.EndpointService.Save(tx, act, data); err != nil {
		rollback()
		return nil, err
	}
	stagedConfig, err := s.getConfigWithDB(tx, "")
	if err != nil {
		rollback()
		return nil, err
	}
	if err = corePtr.ValidateConfig(*stagedConfig); err != nil {
		rollback()
		return nil, common.NewErrorf("sing-box configuration check failed: %v", err)
	}
	if err = tx.Create(&model.Changes{
		DateTime: time.Now().Unix(), Actor: loginUser, Key: "endpoints", Action: act, Obj: redactChangeData(data),
	}).Error; err != nil {
		rollback()
		return nil, err
	}
	if apply {
		if err = s.restartCoreWithRaw(*stagedConfig); err != nil {
			rollback()
			if rollbackErr := s.restartCoreWithRaw(*oldConfig); rollbackErr != nil {
				return nil, common.NewErrorf("apply failed: %v; restoring the previous runtime also failed: %v", err, rollbackErr)
			}
			return nil, common.NewErrorf("apply failed and the previous runtime was restored: %v", err)
		}
	}
	if err = tx.Commit().Error; err != nil {
		if apply {
			_ = s.restartCoreWithRaw(*oldConfig)
		}
		return nil, err
	}
	LastUpdate = time.Now().Unix()
	return []string{"endpoints"}, nil
}

func redactChangeData(data json.RawMessage) json.RawMessage {
	var value interface{}
	if json.Unmarshal(data, &value) != nil {
		return data
	}
	var redact func(interface{})
	redact = func(current interface{}) {
		switch typed := current.(type) {
		case map[string]interface{}:
			for key, child := range typed {
				lower := strings.ToLower(key)
				if strings.Contains(lower, "private_key") || strings.Contains(lower, "pre_shared_key") || strings.Contains(lower, "preshared") || strings.Contains(lower, "password") || strings.Contains(lower, "secret") || strings.Contains(lower, "token") {
					typed[key] = "[redacted]"
					continue
				}
				redact(child)
			}
		case []interface{}:
			for _, child := range typed {
				redact(child)
			}
		}
	}
	redact(value)
	redacted, err := json.Marshal(value)
	if err != nil {
		return data
	}
	return redacted
}

func injectManagedRoutes(db *gorm.DB, raw json.RawMessage) (json.RawMessage, error) {
	route := map[string]interface{}{}
	if len(raw) > 0 && string(raw) != "null" {
		if err := json.Unmarshal(raw, &route); err != nil {
			return nil, err
		}
	}
	rules := listValue(route["rules"])
	var managed []model.ManagedRouteRule
	if err := db.Order("managed_key asc").Find(&managed).Error; err != nil {
		return nil, err
	}
	for _, item := range managed {
		cidrs := managedRouteCIDRs(item)
		inbounds := managedRouteInbounds(item)
		if len(cidrs) == 0 || len(inbounds) == 0 || containsManagedRoute(rules, inbounds, item.EndpointTag, cidrs) {
			continue
		}
		rules = append(rules, map[string]interface{}{
			"inbound": inbounds, "ip_cidr": cidrs,
			"action": "route", "outbound": item.EndpointTag,
		})
	}
	route["rules"] = rules
	return json.Marshal(route)
}

func managedRouteCIDRs(item model.ManagedRouteRule) []string {
	if strings.TrimSpace(item.CIDRs) != "" {
		var cidrs []string
		if err := json.Unmarshal([]byte(item.CIDRs), &cidrs); err == nil {
			return cidrs
		}
	}
	cidrs := make([]string, 0, 2)
	if item.IPv4CIDR != "" {
		cidrs = append(cidrs, item.IPv4CIDR)
	}
	if item.IPv6CIDR != "" {
		cidrs = append(cidrs, item.IPv6CIDR)
	}
	return cidrs
}

func managedRouteInbounds(item model.ManagedRouteRule) []string {
	if strings.TrimSpace(item.InboundTags) != "" {
		var inbounds []string
		if err := json.Unmarshal([]byte(item.InboundTags), &inbounds); err == nil && len(inbounds) > 0 {
			return inbounds
		}
	}
	if item.EndpointTag == "" {
		return nil
	}
	return []string{item.EndpointTag}
}

func containsManagedRoute(rules []interface{}, inbounds []string, tag string, cidrs []string) bool {
	wanted := append([]string(nil), cidrs...)
	sort.Strings(wanted)
	wantedInbounds := append([]string(nil), inbounds...)
	sort.Strings(wantedInbounds)
	for _, rawRule := range rules {
		rule := mapValue(rawRule)
		if rule == nil || stringValue(rule["action"]) != "route" || stringValue(rule["outbound"]) != tag {
			continue
		}
		actualInbounds := stringsValue(rule["inbound"])
		sort.Strings(actualInbounds)
		actual := stringsValue(rule["ip_cidr"])
		sort.Strings(actual)
		if strings.Join(actualInbounds, "\x00") == strings.Join(wantedInbounds, "\x00") &&
			strings.Join(actual, "\x00") == strings.Join(wanted, "\x00") {
			return true
		}
	}
	return false
}

func (s *ConfigService) CheckChanges(lu string) (bool, error) {
	if lu == "" {
		return true, nil
	}
	if LastUpdate == 0 {
		db := database.GetDB()
		var count int64
		err := db.Model(model.Changes{}).Where("date_time > " + lu).Count(&count).Error
		if err == nil {
			LastUpdate = time.Now().Unix()
		}
		return count > 0, err
	} else {
		intLu, err := strconv.ParseInt(lu, 10, 64)
		return LastUpdate > intLu, err
	}
}

func (s *ConfigService) GetChanges(actor string, chngKey string, count string) []model.Changes {
	limit, _ := strconv.Atoi(count)
	result, err := s.QueryChanges(ChangesFilter{Actor: actor, Key: chngKey, Limit: limit})
	if err != nil {
		logger.Warning(err)
		return []model.Changes{}
	}
	return result.Items
}
