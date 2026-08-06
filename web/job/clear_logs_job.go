package job

import (
	"io"
	"os"
	"path/filepath"

	"github.com/mhsanaei/3x-ui/v2/logger"
	"github.com/mhsanaei/3x-ui/v2/xray"
)

// ClearLogsJob clears old log files to prevent disk space issues.
type ClearLogsJob struct{}

// NewClearLogsJob creates a new log cleanup job instance.
func NewClearLogsJob() *ClearLogsJob {
	return new(ClearLogsJob)
}

// ensureFileExists creates the necessary directories and file if they don't exist
func ensureFileExists(path string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return err
	}
	file.Close()
	return nil
}

// rotateLogFile copies the current contents of path to a ".prev" sibling and truncates
// the original, bounding unbounded growth. It is used for non-audit logs (Xray file logs
// and the panel log) that the audit-log loop below does not cover (see review L3).
//
// NOTE: for files the process keeps open (e.g. the panel's 3xui.log held by logger), a
// true copytruncate would require the writer to reopen; this copy+truncate is best-effort.
// For strict rotation of an open file, deploy an external logrotate(8) configuration.
func (j *ClearLogsJob) rotateLogFile(path string) {
	info, err := os.Stat(path)
	if err != nil {
		// File absent: e.g. Xray file logging disabled or panel log not yet written.
		return
	}
	if info.Size() == 0 {
		return
	}

	src, err := os.Open(path)
	if err != nil {
		logger.Warning("Failed to open log for rotation:", path, "-", err)
		return
	}
	defer src.Close()

	prevPath := path + ".prev"
	dst, err := os.OpenFile(prevPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		logger.Warning("Failed to open previous log for rotation:", prevPath, "-", err)
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		logger.Warning("Failed to rotate log file:", path, "-", err)
		return
	}
	if err := os.Truncate(path, 0); err != nil {
		logger.Warning("Failed to truncate log file:", path, "-", err)
	}
}

// collectExtraLogPaths returns the non-audit log paths to rotate: Xray file logs (only
// when the Xray config enables them) and the panel log (3xui.log).
func (j *ClearLogsJob) collectExtraLogPaths() []string {
	var paths []string

	if access, err := xray.GetAccessLogPath(); err == nil && isRealLogPath(access) {
		paths = append(paths, access)
	}
	if errPath, ok := xray.GetErrorLogPath(); ok && isRealLogPath(errPath) {
		paths = append(paths, errPath)
	}
	if panel := xray.GetPanelLogPath(); panel != "" {
		paths = append(paths, panel)
	}
	return paths
}

// isRealLogPath filters out Xray "log" values that are not file paths
// ("none", "stdout", "stderr") so we never try to rotate a pseudo-sink.
func isRealLogPath(p string) bool {
	switch p {
	case "", "none", "stdout", "stderr":
		return false
	}
	return true
}

// Here Run is an interface method of the Job interface
func (j *ClearLogsJob) Run() {
	logFiles := []string{xray.GetIPLimitLogPath(), xray.GetIPLimitBannedLogPath(), xray.GetAccessPersistentLogPath()}
	logFilesPrev := []string{xray.GetIPLimitBannedPrevLogPath(), xray.GetAccessPersistentPrevLogPath()}

	// Ensure all log files and their paths exist
	for _, path := range append(logFiles, logFilesPrev...) {
		if err := ensureFileExists(path); err != nil {
			logger.Warning("Failed to ensure log file exists:", path, "-", err)
		}
	}

	// Clear log files and copy to previous logs
	for i := range len(logFiles) {
		if i > 0 {
			// Copy to previous logs
			logFilePrev, err := os.OpenFile(logFilesPrev[i-1], os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
			if err != nil {
				logger.Warning("Failed to open previous log file for writing:", logFilesPrev[i-1], "-", err)
				continue
			}

			logFile, err := os.OpenFile(logFiles[i], os.O_RDONLY, 0644)
			if err != nil {
				logger.Warning("Failed to open current log file for reading:", logFiles[i], "-", err)
				logFilePrev.Close()
				continue
			}

			_, err = io.Copy(logFilePrev, logFile)
			if err != nil {
				logger.Warning("Failed to copy log file:", logFiles[i], "to", logFilesPrev[i-1], "-", err)
			}

			logFile.Close()
			logFilePrev.Close()
		}

		err := os.Truncate(logFiles[i], 0)
		if err != nil {
			logger.Warning("Failed to truncate log file:", logFiles[i], "-", err)
		}
	}

	// Rotate non-audit logs (Xray file logs + panel log) so long-running deployments
	// don't grow them without bound. Audit logs above are handled with previous-copy.
	for _, path := range j.collectExtraLogPaths() {
		j.rotateLogFile(path)
	}
}
