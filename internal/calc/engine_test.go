package calc

import (
	"testing"

	"weirdgungamecalc/internal/model"
)

func TestBuildGunBaseline(t *testing.T) {
	core := model.Core{Name: "Core", Category: "AR", Damage: 25.0, FireRate: 600, HipfireSpread: 1, ADSSpread: 1, TimeToAim: 0.2, DetectionRadius: 100, Pellets: 1, Burst: 1, DropoffStuds: [2]float64{100, 200}}
	mag := model.Part{Name: "Mag", Category: "AR", MagazineSize: 30, ReloadTime: 2}
	barrel := model.Part{Name: "Barrel", Category: "AR"}
	stock := model.Part{Name: "Stock", Category: "AR"}
	grip := model.Part{Name: "Grip", Category: "AR"}

	g := buildGun(core, mag, barrel, stock, grip, nil, 100)

	if g.TTKMinutes <= 0 {
		t.Fatalf("expected positive ttk, got %v", g.TTKMinutes)
	}
	if g.Damage != 25 {
		t.Fatalf("expected damage 25, got %v", g.Damage)
	}
	if g.DPM != 15000 {
		t.Fatalf("expected dpm 15000, got %v", g.DPM)
	}
}

func TestPassesFilters(t *testing.T) {
	g := model.Gun{Damage: 10, DamageEnd: 8, MagazineSize: 12, SpreadHip: 1, SpreadAim: 1, RecoilHip: 1, RecoilAim: 1, MovementSpeed: 0, FireRate: 100, Health: 0, Pellets: 1, TimeToAim: 0.2, ReloadTime: 2, DetectionRadius: 10, DropoffStart: 50, DropoffEnd: 100, Burst: 1, TTKMinutes: 0.1, DPM: 1000}
	f := DefaultOptions().Filters
	f.Damage = Range{Min: 9, Max: 11}
	f.TTK = Range{Min: 0, Max: 1}
	if !passesFilters(g, f) {
		t.Fatal("expected gun to pass filters")
	}
	f.Damage = Range{Min: 11, Max: 20}
	if passesFilters(g, f) {
		t.Fatal("expected gun to fail damage filter")
	}
}

func TestTopNSortByTTK(t *testing.T) {
	guns := []model.Gun{{Core: "A", TTKMinutes: 0.4}, {Core: "B", TTKMinutes: 0.2}, {Core: "C", TTKMinutes: 0.3}}
	got := topN(guns, 2, SortTTK, false)
	if len(got) != 2 {
		t.Fatalf("expected 2 got %d", len(got))
	}
	if got[0].Core != "B" || got[1].Core != "C" {
		t.Fatalf("unexpected order: %+v", got)
	}
}
