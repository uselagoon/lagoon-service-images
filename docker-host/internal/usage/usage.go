package usage

import (
	"context"
	"fmt"
	"log"
	"math"
	"strings"

	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/client"
	human "github.com/dustin/go-humanize"
	"github.com/robfig/cron/v3"
	"github.com/shirou/gopsutil/disk"
)

type Usage struct {
	Client             *client.Client
	Cron               *cron.Cron
	UsageSchedule      string
	VolumePath         string
	VolumeMinThreshold float64
	VolumeMaxThreshold float64
	InodeMinThreshold  float64
	InodeMaxThreshold  float64
	PruneImagesUntil   string
}

func (u *Usage) CheckUsageCron() {
	_, err := u.Cron.AddFunc(u.UsageSchedule, func() {
		formatter := "%-14s %7s %7s %7s %4s %7s %7s %7s %4s %s\n"
		fmt.Printf(formatter, "Filesystem", "Size", "Used", "Avail", "Use%", "iSize", "iUsed", "iAvail", "iUse%", "Mounted on")

		s, _ := disk.Usage(u.VolumePath)
		percent := fmt.Sprintf("%2.f%%", s.UsedPercent)
		iPercent := fmt.Sprintf("%2.f%%", s.InodesUsedPercent)
		perc := math.Round(s.UsedPercent)
		iPerc := math.Round(s.InodesUsedPercent)

		printStats := false
		if perc > u.VolumeMinThreshold && perc > u.VolumeMaxThreshold {
			log.Printf("volume max threshold exceeded\n")
			printStats = true
			// check images and cache
		}
		if iPerc > u.InodeMinThreshold && iPerc > u.InodeMaxThreshold {
			log.Printf("inode max threshold exceeded\n")
			// check images and cache
			printStats = true
		}
		if printStats {
			fmt.Printf(formatter,
				s.Fstype,
				human.Bytes(s.Total),
				human.Bytes(s.Used),
				human.Bytes(s.Free),
				percent,
				human.Bytes(s.InodesTotal),
				human.Bytes(s.InodesUsed),
				human.Bytes(s.InodesFree),
				iPercent,
				u.VolumePath,
			)

			// ageFilter := filters.NewArgs()
			// ageFilter.Add("until", u.PruneImagesUntil)
			lsOpts := image.ListOptions{
				All: true,
				// Filters: ageFilter,
			}
			imageList, err := u.Client.ImageList(context.Background(), lsOpts)
			if err != nil {
				log.Println(err)
				return
			}
			var totalImageSize int64
			for _, image := range imageList {
				fmt.Printf("Image: %s, %s, %d, %d, %d\n", image.ID, strings.Join(image.RepoTags, "|"), image.Created, image.Size, image.SharedSize)
				totalImageSize = totalImageSize + image.Size
			}
			fmt.Printf("Total Image Size: %d\n", totalImageSize)
		}
	})

	if err != nil {
		log.Printf("Error initiating checkUsage cron: %v\n", err)
	}
}
