package controller

import (
	"encoding/json"

	"github.com/mhsanaei/3x-ui/v3/internal/web/service"

	"github.com/gin-gonic/gin"
)

// VPNGateController exposes the VPNGate-over-WARP management API. All routes
// live under /panel/api/vpngate and inherit the API auth + CSRF middleware
// mounted by APIController (see api.go). The heavy lifting (node fetch/validate,
// OpenVPN policy routing, xray freedom outbound, failover watchdog) is performed
// by service.OpenVPNService / service.VPNGateService, which were ported from the
// v1.2.0 CatVPN line during the v3.6.0 rebase.
type VPNGateController struct {
	BaseController
	vpnGateService  service.VPNGateService
	openVPNService  *service.OpenVPNService
	settingService  service.SettingService
}

// NewVPNGateController creates a new VPNGateController and initializes its routes.
func NewVPNGateController(g *gin.RouterGroup) *VPNGateController {
	a := &VPNGateController{
		openVPNService: &service.OpenVPNService{},
	}
	a.initRouter(g)
	return a
}

func (a *VPNGateController) initRouter(g *gin.RouterGroup) {
	v := g.Group("/vpngate")

	// Read endpoints
	v.GET("/servers", a.getServers)
	v.GET("/status", a.getStatus)
	v.GET("/settings", a.getSettings)

	// Mutating endpoints
	v.POST("/settings", a.updateSettings)
	v.POST("/start", a.start)
	v.POST("/stop", a.stop)
	v.POST("/cancel", a.cancel)
	v.POST("/repair", a.repair)
	v.POST("/refresh", a.refresh)
}

// startVPNGateForm carries the chosen VPNGate server plus the egress rule
// options used by OpenVPNService.StartVPNGate.
type startVPNGateForm struct {
	Server            service.VPNGateServer `json:"server"`
	RuleMode          string                `json:"ruleMode"`
	SelectedCountries []string              `json:"selectedCountries"`
	FallbackEnable    bool                  `json:"fallbackEnable"`
}

// updateVPNGateSettingsForm carries the persisted egress preferences.
type updateVPNGateSettingsForm struct {
	RuleMode          string   `json:"ruleMode"`
	SelectedCountries []string `json:"selectedCountries"`
	FallbackEnable    bool     `json:"fallbackEnable"`
}

// getServers returns the current VPNGate server list. ?refresh=true forces a
// fresh pull from the VPNGate mirror; ?includeUnavailable=true also returns
// nodes that failed the TCP/OpenVPN reachability probe.
func (a *VPNGateController) getServers(c *gin.Context) {
	refresh := c.Query("refresh") == "true" || c.Query("refresh") == "1"
	includeUnavailable := c.Query("includeUnavailable") == "true" || c.Query("includeUnavailable") == "1"

	servers, err := a.vpnGateService.ListServersWithUnavailable(refresh, includeUnavailable)
	if err != nil {
		jsonMsg(c, "获取 VPNGate 节点列表失败", err)
		return
	}
	jsonObj(c, servers, nil)
}

// getStatus returns the live OpenVPN-over-WARP connection status (phase,
// progress, tun device/IP, bound server, recent log tail).
func (a *VPNGateController) getStatus(c *gin.Context) {
	status := a.openVPNService.VPNGateStatus()
	jsonObj(c, status, nil)
}

// getSettings returns the persisted VPNGate egress preferences.
func (a *VPNGateController) getSettings(c *gin.Context) {
	ruleMode, err := a.settingService.GetVPNGateRuleMode()
	if err != nil {
		jsonMsg(c, "读取 VPNGate 设置失败", err)
		return
	}
	countries, err := a.settingService.GetVPNGateSelectedCountries()
	if err != nil {
		jsonMsg(c, "读取 VPNGate 设置失败", err)
		return
	}
	fallback, err := a.settingService.GetVPNGateFallbackEnable()
	if err != nil {
		jsonMsg(c, "读取 VPNGate 设置失败", err)
		return
	}
	jsonObj(c, gin.H{
		"ruleMode":          ruleMode,
		"selectedCountries": countries,
		"fallbackEnable":    fallback,
	}, nil)
}

// updateSettings persists the VPNGate egress preferences.
func (a *VPNGateController) updateSettings(c *gin.Context) {
	var f updateVPNGateSettingsForm
	if err := c.ShouldBindJSON(&f); err != nil {
		jsonMsg(c, "请求参数解析失败", err)
		return
	}
	if f.RuleMode == "" {
		f.RuleMode = "default"
	}
	if f.SelectedCountries == nil {
		f.SelectedCountries = []string{}
	}
	if err := a.settingService.SetVPNGateRuleMode(f.RuleMode); err != nil {
		jsonMsg(c, "保存规则模式失败", err)
		return
	}
	countriesJSON, err := json.Marshal(f.SelectedCountries)
	if err != nil {
		jsonMsg(c, "序列化国家选择失败", err)
		return
	}
	if err := a.settingService.SetVPNGateSelectedCountries(string(countriesJSON)); err != nil {
		jsonMsg(c, "保存国家选择失败", err)
		return
	}
	if err := a.settingService.SetVPNGateFallbackEnable(f.FallbackEnable); err != nil {
		jsonMsg(c, "保存故障转移开关失败", err)
		return
	}
	jsonMsg(c, "VPNGate 设置已保存", nil)
}

// start brings up the chosen VPNGate node as an xray freedom outbound routed
// through the host-level wg-warp interface.
func (a *VPNGateController) start(c *gin.Context) {
	var f startVPNGateForm
	if err := c.ShouldBindJSON(&f); err != nil {
		jsonMsg(c, "请求参数解析失败", err)
		return
	}
	if f.Server.IP == "" || f.Server.OpenVPNConfig == "" {
		jsonMsg(c, "未指定有效的 VPNGate 节点", nil)
		return
	}
	if f.RuleMode == "" {
		f.RuleMode = "default"
	}
	if f.SelectedCountries == nil {
		f.SelectedCountries = []string{}
	}
	status, err := a.openVPNService.StartVPNGate(f.Server, f.RuleMode, f.SelectedCountries, f.FallbackEnable)
	if err != nil {
		jsonMsg(c, "启动 VPNGate 连接失败", err)
		return
	}
	jsonObj(c, status, nil)
}

// stop tears down the VPNGate tunnel and removes the xray outbound.
func (a *VPNGateController) stop(c *gin.Context) {
	status := a.openVPNService.StopVPNGate()
	jsonObj(c, status, nil)
}

// cancel aborts an in-progress connection attempt without waiting for it to finish.
func (a *VPNGateController) cancel(c *gin.Context) {
	status := a.openVPNService.CancelVPNGate()
	jsonObj(c, status, nil)
}

// repair attempts to detect and recover a dropped VPNGate outbound.
func (a *VPNGateController) repair(c *gin.Context) {
	repaired := a.openVPNService.CheckAndRepairVPNGate()
	jsonObj(c, gin.H{"repaired": repaired}, nil)
}

// refresh forces an immediate node-list refresh plus stale-outbound recovery,
// mirroring the background @every 1m cron tick on demand.
func (a *VPNGateController) refresh(c *gin.Context) {
	service.CheckAndRefreshVPNGate(0)
	a.openVPNService.RecoverStaleVPNGateOutbound()
	jsonMsg(c, "VPNGate 节点刷新已触发", nil)
}
