// Package job provides background job implementations for the 3x-ui web panel,
// including traffic monitoring, system checks, and periodic maintenance tasks.
package job

import (
	"sync/atomic"

	"github.com/mhsanaei/3x-ui/v2/logger"
	"github.com/mhsanaei/3x-ui/v2/web/service"
)

// CheckXrayRunningJob monitors Xray process health and restarts it if it crashes.
//
// Single-responsibility / division of labor (see review L10):
//   - Xray is a CHILD process of the panel. Its crash recovery is owned entirely by
//     this job, which calls service.RestartXray. systemd never restarts xray.
//   - systemd's `Restart=on-failure` on the x-ui.service unit only supervises the
//     PANEL process (x-ui) itself. It is NOT involved in xray's lifecycle, so there is
//     no double-restart of xray. (If the panel crashes, systemd restarts the panel, and
//     the panel's normal startup brings xray back up — also not a double restart.)
//   - This job therefore must NEVER shell out to `systemctl` to manage xray; doing so
//     would only risk racing systemd's management of the panel process.
type CheckXrayRunningJob struct {
	xrayService service.XrayService
	checkTime   int
	// restarting guards against re-entrant / overlapping restarts when the job ticks
	// again before the previous restart has fully settled. It is a best-effort debounce
	// layered on top of the 2-consecutive-crash check below.
	restarting atomic.Bool
}

// NewCheckXrayRunningJob creates a new Xray health check job instance.
func NewCheckXrayRunningJob() *CheckXrayRunningJob {
	return new(CheckXrayRunningJob)
}

// Run checks if Xray has crashed and restarts it after confirming it's down for 2 consecutive checks.
func (j *CheckXrayRunningJob) Run() {
	if !j.xrayService.DidXrayCrash() {
		j.checkTime = 0
		return
	}

	j.checkTime++
	// only restart if it's down 2 times in a row (debounce against transient blips)
	if j.checkTime <= 1 {
		return
	}

	// Skip this tick if a previous restart is still in progress to avoid overlapping
	// restarts that could fight each other (and, by design, never touch systemctl).
	if !j.restarting.CompareAndSwap(false, true) {
		logger.Warning("Xray restart already in progress, skipping this tick")
		return
	}
	defer j.restarting.Store(false)

	j.checkTime = 0
	err := j.xrayService.RestartXray(false)
	if err != nil {
		logger.Error("Restart xray failed:", err)
	}
}
