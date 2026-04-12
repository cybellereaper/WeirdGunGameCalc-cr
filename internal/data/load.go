package data

import (
	"encoding/json"
	"fmt"
	"os"

	"weirdgungamecalc/internal/model"
)

type rawDataset struct {
	Data struct {
		Barrels   []model.Part `json:"Barrels"`
		Magazines []model.Part `json:"Magazines"`
		Grips     []model.Part `json:"Grips"`
		Stocks    []model.Part `json:"Stocks"`
		Cores     []model.Core `json:"Cores"`
	} `json:"Data"`
	Categories struct {
		Primary   map[string]int `json:"Primary"`
		Secondary map[string]int `json:"Secondary"`
	} `json:"Categories"`
	Penalties [][]float64 `json:"Penalties"`
}

func LoadDataset(path string) (model.Dataset, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return model.Dataset{}, fmt.Errorf("read dataset: %w", err)
	}

	var raw rawDataset
	if err := json.Unmarshal(bytes, &raw); err != nil {
		return model.Dataset{}, fmt.Errorf("parse dataset json: %w", err)
	}

	penalties := make(map[string]map[string]float64)
	indexToCategory := make(map[int]string)
	for category, index := range raw.Categories.Primary {
		indexToCategory[index] = category
	}
	for category, index := range raw.Categories.Secondary {
		indexToCategory[index] = category
	}

	for i, row := range raw.Penalties {
		coreCategory := indexToCategory[i]
		if coreCategory == "" {
			continue
		}
		penalties[coreCategory] = make(map[string]float64)
		for j, value := range row {
			partCategory := indexToCategory[j]
			if partCategory == "" {
				continue
			}
			penalties[coreCategory][partCategory] = value
		}
	}

	return model.Dataset{
		Cores:     raw.Data.Cores,
		Barrels:   raw.Data.Barrels,
		Magazines: raw.Data.Magazines,
		Grips:     raw.Data.Grips,
		Stocks:    raw.Data.Stocks,
		Penalties: penalties,
	}, nil
}
