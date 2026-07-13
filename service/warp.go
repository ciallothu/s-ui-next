package service

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/ciallothu/s-ui-next/database/model"
	"github.com/ciallothu/s-ui-next/util/common"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

type WarpService struct{}

const maxWarpResponseBytes int64 = 1 << 20

var warpHTTPClient = &http.Client{Timeout: 30 * time.Second}

func (s *WarpService) getWarpInfo(deviceId string, accessToken string) ([]byte, error) {
	url := fmt.Sprintf("https://api.cloudflareclient.com/v0a2158/reg/%s", deviceId)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)

	resp, err := warpHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, common.NewErrorf("warp API returned HTTP %d: %s", resp.StatusCode, readWarpResponse(resp))
	}
	return readWarpBody(resp)
}

func (s *WarpService) RegisterWarp(ep *model.Endpoint) error {
	tos := time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
	privateKey, _ := wgtypes.GenerateKey()
	publicKey := privateKey.PublicKey().String()
	hostName, _ := os.Hostname()

	data := fmt.Sprintf(`{"key":"%s","tos":"%s","type": "PC","model": "s-ui-next", "name": "%s"}`, publicKey, tos, hostName)
	url := "https://api.cloudflareclient.com/v0a2158/reg"

	req, err := http.NewRequest("POST", url, bytes.NewBuffer([]byte(data)))
	if err != nil {
		return err
	}

	req.Header.Add("CF-Client-Version", "a-7.21-0721")
	req.Header.Add("Content-Type", "application/json")

	resp, err := warpHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return common.NewErrorf("warp registration returned HTTP %d: %s", resp.StatusCode, readWarpResponse(resp))
	}
	responseBody, err := readWarpBody(resp)
	if err != nil {
		return err
	}

	var rspData map[string]interface{}
	err = json.Unmarshal(responseBody, &rspData)
	if err != nil {
		return err
	}

	deviceId, _ := rspData["id"].(string)
	token, _ := rspData["token"].(string)
	account, _ := rspData["account"].(map[string]interface{})
	license, _ := account["license"].(string)
	if deviceId == "" || token == "" || license == "" {
		return common.NewError("warp registration response is missing device credentials")
	}

	warpInfo, err := s.getWarpInfo(deviceId, token)
	if err != nil {
		return err
	}

	var warpDetails map[string]interface{}
	err = json.Unmarshal(warpInfo, &warpDetails)
	if err != nil {
		return err
	}

	warpConfig, _ := warpDetails["config"].(map[string]interface{})
	if warpConfig == nil {
		return common.NewError("warp device response is missing config")
	}
	clientId, _ := warpConfig["client_id"].(string)
	reserved := s.getReserved(clientId)
	interfaceConfig, _ := warpConfig["interface"].(map[string]interface{})
	addresses, _ := interfaceConfig["addresses"].(map[string]interface{})
	v4, _ := addresses["v4"].(string)
	v6, _ := addresses["v6"].(string)
	peersRaw, _ := warpConfig["peers"].([]interface{})
	if len(peersRaw) == 0 {
		return common.NewError("warp device response is missing peers")
	}
	peer, _ := peersRaw[0].(map[string]interface{})
	endpoint, _ := peer["endpoint"].(map[string]interface{})
	peerEndpoint, _ := endpoint["host"].(string)
	peerEpAddress, peerEpPort, err := net.SplitHostPort(peerEndpoint)
	if err != nil {
		return err
	}
	peerPublicKey, _ := peer["public_key"].(string)
	peerPort, _ := strconv.Atoi(peerEpPort)
	if v4 == "" || v6 == "" || peerPublicKey == "" || peerPort == 0 {
		return common.NewError("warp device response is incomplete")
	}

	peers := []map[string]interface{}{
		{
			"address":     peerEpAddress,
			"port":        peerPort,
			"public_key":  peerPublicKey,
			"allowed_ips": []string{"0.0.0.0/0", "::/0"},
			"reserved":    reserved,
		},
	}

	warpData := map[string]interface{}{
		"access_token": token,
		"device_id":    deviceId,
		"license_key":  license,
	}

	ep.Ext, err = json.MarshalIndent(warpData, "", "  ")
	if err != nil {
		return err
	}

	var epOptions map[string]interface{}
	err = json.Unmarshal(ep.Options, &epOptions)
	if err != nil {
		return err
	}
	epOptions["private_key"] = privateKey.String()
	epOptions["address"] = []string{fmt.Sprintf("%s/32", v4), fmt.Sprintf("%s/128", v6)}
	epOptions["listen_port"] = 0
	epOptions["peers"] = peers

	ep.Options, err = json.MarshalIndent(epOptions, "", "  ")
	return err
}

func (s *WarpService) getReserved(clientID string) []int {
	var reserved []int
	decoded, err := base64.StdEncoding.DecodeString(clientID)
	if err != nil {
		return nil
	}

	hexString := ""
	for _, char := range decoded {
		hex := fmt.Sprintf("%02x", char)
		hexString += hex
	}

	for i := 0; i < len(hexString); i += 2 {
		hexByte := hexString[i : i+2]
		decValue, err := strconv.ParseInt(hexByte, 16, 32)
		if err != nil {
			return nil
		}
		reserved = append(reserved, int(decValue))
	}

	return reserved
}

func (s *WarpService) SetWarpLicense(old_license string, ep *model.Endpoint) error {
	var warpData map[string]string
	err := json.Unmarshal(ep.Ext, &warpData)
	if err != nil {
		return err
	}
	if warpData["device_id"] == "" || warpData["access_token"] == "" {
		return common.NewError("warp device credentials are missing")
	}

	if warpData["license_key"] == old_license {
		return nil
	}

	url := fmt.Sprintf("https://api.cloudflareclient.com/v0a2158/reg/%s/account", warpData["device_id"])
	data := fmt.Sprintf(`{"license": "%s"}`, warpData["license_key"])

	req, err := http.NewRequest("PUT", url, bytes.NewBuffer([]byte(data)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+warpData["access_token"])

	resp, err := warpHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return common.NewErrorf("warp license update returned HTTP %d: %s", resp.StatusCode, readWarpResponse(resp))
	}
	responseBody, err := readWarpBody(resp)
	if err != nil {
		return err
	}
	var response map[string]interface{}
	err = json.Unmarshal(responseBody, &response)
	if err != nil {
		return err
	}

	if success, ok := response["success"].(bool); ok && success == false {
		errorArr, _ := response["errors"].([]interface{})
		if len(errorArr) > 0 {
			if errorObj, ok := errorArr[0].(map[string]interface{}); ok {
				return common.NewError(errorObj["code"], errorObj["message"])
			}
		}
		return common.NewError("warp license update failed")
	}

	return nil
}

func readWarpResponse(resp *http.Response) string {
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	return string(body)
}

func readWarpBody(resp *http.Response) ([]byte, error) {
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxWarpResponseBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > maxWarpResponseBytes {
		return nil, common.NewError("warp API response is too large")
	}
	return body, nil
}
