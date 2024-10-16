package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"

	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
	"github.com/uselagoon/lagoon-service-images/docker-host/internal/cache"
	"github.com/uselagoon/lagoon-service-images/docker-host/internal/containers"
	"github.com/uselagoon/lagoon-service-images/docker-host/internal/images"
	"github.com/uselagoon/lagoon-service-images/docker-host/internal/usage"
	machineryvars "github.com/uselagoon/machinery/utils/variables"
)

const EnvOverrideHost = "DOCKER_HOST"

var dockerHost = machineryvars.GetEnv("DOCKER_HOST", "docker-host")
var repositoriesToUpdate = machineryvars.GetEnv("REPOSITORIES_TO_UPDATE", "uselagoon")
var registry = machineryvars.GetEnv("REGISTRY", "docker-registry.default.svc:5000")
var bip = machineryvars.GetEnv("BIP", "172.16.0.1/16")
var logLevel = machineryvars.GetEnv("LOG_LEVEL", "info")
var registryMirror = machineryvars.GetEnv("REGISTRY_MIRROR", "")
var pruneImagesSchedule = machineryvars.GetEnv("PRUNE_SCHEDULE", "22 1 * * *")
var pruneDanglingSchedule = machineryvars.GetEnv("PRUNE_DANGLING_SCHEDULE", "22 1 * * *")
var pruneBuilderCacheSchedule = machineryvars.GetEnv("PRUNE_BUILDER_CACHE_SCHEDULE", "22 1 * * *")
var removeExitedSchedule = machineryvars.GetEnv("REMOVE_EXITED_SCHEDULE", "22 */4 * * *")
var updateImagesSchedule = machineryvars.GetEnv("UPDATE_IMAGES_SCHEDULE", "*/15 * * * *")
var usageCheckSchedule = machineryvars.GetEnv("USAGE_CHECK_SCHEDULE", "0 * * * *")
var pruneImagesUntil = machineryvars.GetEnv("PRUNE_IMAGES_UNTIL", "168h")
var pruneBuilderCacheUntil = machineryvars.GetEnv("PRUNE_BUILDER_CACHE_UNTIL", "168h")

func main() {
	cli, err := client.NewClientWithOpts(
		client.WithHostFromEnv(),
		client.WithAPIVersionNegotiation(),
	)
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	defer cli.Close()

	var command = fmt.Sprintf("/usr/local/bin/dind /usr/local/bin/dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --bip=%s --storage-driver=overlay2 --tls=false --log-level=%s", bip, logLevel)
	if registry != "" {
		command = command + fmt.Sprintf(" --insecure-registry=%s", registry)
	}
	if registryMirror != "" {
		command = command + fmt.Sprintf(" --registry-mirror=%s", registryMirror)
	}
	var cmd = exec.Command("sh", "-c", command)

	if dockerHost != cli.DaemonHost() {
		log.Fatalf("Could not connect to %s", dockerHost)
	}
	c := cron.New()
	images := images.Images{
		Cron:                       c,
		Client:                     cli,
		Repositories:               repositoriesToUpdate,
		UpdateSchedule:             updateImagesSchedule,
		PruneImageSchedule:         pruneImagesSchedule,
		PruneImagesUntil:           pruneImagesUntil,
		PruneDanglingImageSchedule: pruneDanglingSchedule,
	}
	containers := containers.Containers{
		Cron:                 c,
		Client:               cli,
		RemoveExitedSchedule: removeExitedSchedule,
	}
	cache := cache.Cache{
		Cron:                      c,
		Client:                    cli,
		PruneBuilderCacheSchedule: pruneBuilderCacheSchedule,
		PruneBuilderCacheUntil:    pruneBuilderCacheUntil,
	}
	usage := usage.Usage{
		Cron:               c,
		Client:             cli,
		VolumePath:         "/var/lib/docker",
		UsageSchedule:      usageCheckSchedule,
		VolumeMinThreshold: 50,
		VolumeMaxThreshold: 85,
		InodeMinThreshold:  50,
		InodeMaxThreshold:  85,
	}
	images.PruneImagesCron()
	images.PruneDanglingImagesCron()
	cache.PruneBuilderCacheCron()
	containers.RemoveExitedCron()
	images.UpdateImagesCron()
	usage.CheckUsageCron()
	c.Start()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		log.Fatalf("could not run command: %v", err)
	}
}
