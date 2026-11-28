// admin_jobs.go — admin view of the daily jobs: recent runs and "run now"
// (docs/pulse/AUTODRAFT.md). Mounted under the admin group, so callers are
// already authenticated admins.
package handlers

import (
	"context"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
)

// recentJobRunsLimit is how many runs GET /admin/jobs returns.
const recentJobRunsLimit = 30

type jobRunner interface {
	Names() []string
	RunNow(ctx context.Context, name string) (string, error)
}

// AdminJobsHandler serves /api/admin/jobs.
type AdminJobsHandler struct {
	runs   *repositories.JobRunRepository
	runner jobRunner
}

// NewAdminJobsHandler builds the handler.
func NewAdminJobsHandler(runs *repositories.JobRunRepository, runner jobRunner) *AdminJobsHandler {
	return &AdminJobsHandler{runs: runs, runner: runner}
}

// List returns the enabled jobs and the latest runs.
func (h *AdminJobsHandler) List(c *gin.Context) {
	runs, err := h.runs.Recent(c.Request.Context(), recentJobRunsLimit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not load job runs"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"enabled": h.runner.Names(), "runs": runs})
}

// RunNow runs one job synchronously and returns its summary: 404 when the
// job is not enabled, 409 while it is already running, 500 if it fails.
// The run is detached from the request, so a dropped connection does not
// cancel it half way.
func (h *AdminJobsHandler) RunNow(c *gin.Context) {
	name := c.Param("name")
	if !containsName(h.runner.Names(), name) {
		c.JSON(http.StatusNotFound, gin.H{"error": "Job is not enabled"})
		return
	}
	detail, err := h.runner.RunNow(context.WithoutCancel(c.Request.Context()), name)
	if errors.Is(err, services.ErrJobAlreadyRunning) {
		c.JSON(http.StatusConflict, gin.H{"error": "Job is already running"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Job failed: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"job": name, "detail": detail})
}

func containsName(names []string, name string) bool {
	for _, n := range names {
		if n == name {
			return true
		}
	}
	return false
}
