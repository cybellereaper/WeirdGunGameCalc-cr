package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"weirdgungamecalc/internal/calc"
	"weirdgungamecalc/internal/data"
)

const version = "3.0.0-go"

func main() {
	opt := calc.DefaultOptions()

	dataPath := flag.String("data", "Data/FullData.json", "Path to FullData.json")
	outputPath := flag.String("output", "Results.json", "Output path")
	topN := flag.Int("number", 10, "Number of top builds")
	sortBy := flag.String("sort", "TTK", "Sort metric")
	priority := flag.String("priority", "AUTO", "AUTO|HIGHEST|LOWEST")
	categories := flag.String("include", "", "Comma-separated categories")
	banPrice := flag.String("banPriceType", "", "Comma-separated price types")
	playerHealth := flag.Float64("defaultMaxHealth", 100, "Player max health used in TTK")
	versionFlag := flag.Bool("version", false, "Print version")

	flag.Parse()

	if *versionFlag {
		fmt.Println(version)
		return
	}

	opt.TopN = *topN
	opt.SortBy = calc.SortBy(strings.ToUpper(*sortBy))
	opt.PlayerMaxHealth = *playerHealth

	if *categories != "" {
		opt.Categories = toSet(*categories)
	}
	if *banPrice != "" {
		opt.BanPrice = toSetUpper(*banPrice)
	}

	switch strings.ToUpper(*priority) {
	case "HIGHEST":
		v := true
		opt.Descending = &v
	case "LOWEST":
		v := false
		opt.Descending = &v
	}

	dataset, err := data.LoadDataset(*dataPath)
	if err != nil {
		fatal(err)
	}

	engine := calc.NewEngine(dataset)
	start := time.Now()
	guns := engine.Calculate(opt)
	duration := time.Since(start)

	payload, err := json.MarshalIndent(struct {
		Version   string      `json:"version"`
		Duration  string      `json:"duration"`
		SortBy    calc.SortBy `json:"sortBy"`
		Count     int         `json:"count"`
		TopBuilds any         `json:"topBuilds"`
	}{
		Version:   version,
		Duration:  duration.String(),
		SortBy:    opt.SortBy,
		Count:     len(guns),
		TopBuilds: guns,
	}, "", "  ")
	if err != nil {
		fatal(err)
	}

	if err := os.WriteFile(*outputPath, payload, 0o644); err != nil {
		fatal(err)
	}

	fmt.Printf("Calculated %d guns in %s. Results written to %s\n", len(guns), duration.String(), *outputPath)
}

func toSet(input string) map[string]bool {
	result := make(map[string]bool)
	for _, part := range strings.Split(input, ",") {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			result[trimmed] = true
		}
	}
	return result
}

func toSetUpper(input string) map[string]bool {
	result := make(map[string]bool)
	for key := range toSet(input) {
		result[strings.ToUpper(key)] = true
	}
	return result
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
