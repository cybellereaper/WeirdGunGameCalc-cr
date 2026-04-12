package model

type Range struct {
	Min float64
	Max float64
}

type RangeStat struct {
	Start float64 `json:"0"`
	End   float64 `json:"1"`
}

type RecoilRange [2]float64

type Core struct {
	PriceType           string      `json:"Price_Type"`
	Name                string      `json:"Name"`
	Category            string      `json:"Category"`
	Damage              any         `json:"Damage"`
	DropoffStuds        [2]float64  `json:"Dropoff_Studs"`
	FireRate            float64     `json:"Fire_Rate"`
	HipfireSpread       float64     `json:"Hipfire_Spread"`
	ADSSpread           float64     `json:"ADS_Spread"`
	TimeToAim           float64     `json:"Time_To_Aim"`
	DetectionRadius     float64     `json:"Detection_Radius"`
	EquipTime           float64     `json:"Equip_Time"`
	RecoilHipHorizontal RecoilRange `json:"Recoil_Hip_Horizontal"`
	RecoilHipVertical   RecoilRange `json:"Recoil_Hip_Vertical"`
	RecoilAimHorizontal RecoilRange `json:"Recoil_Aim_Horizontal"`
	RecoilAimVertical   RecoilRange `json:"Recoil_Aim_Vertical"`
	Pellets             float64     `json:"Pellets"`
	Burst               float64     `json:"Burst"`
	Health              float64     `json:"Health"`
	MovementSpeedMod    float64     `json:"Movement_Speed_Modifier"`
}

type Part struct {
	PriceType       string  `json:"Price_Type"`
	Name            string  `json:"Name"`
	Category        string  `json:"Category"`
	Damage          float64 `json:"Damage"`
	FireRate        float64 `json:"Fire_Rate"`
	Spread          float64 `json:"Spread"`
	Recoil          float64 `json:"Recoil"`
	ReloadSpeed     float64 `json:"Reload_Speed"`
	MagazineCap     float64 `json:"Magazine_Cap"`
	MagazineSize    float64 `json:"Magazine_Size"`
	ReloadTime      float64 `json:"Reload_Time"`
	MovementSpeed   float64 `json:"Movement_Speed"`
	Health          float64 `json:"Health"`
	EquipTime       float64 `json:"Equip_Time"`
	Pellets         float64 `json:"Pellets"`
	DetectionRadius float64 `json:"Detection_Radius"`
	Range           float64 `json:"Range"`
}

type Dataset struct {
	Cores     []Core
	Barrels   []Part
	Magazines []Part
	Grips     []Part
	Stocks    []Part
	Penalties map[string]map[string]float64
}

type Gun struct {
	Core     string
	Barrel   string
	Magazine string
	Grip     string
	Stock    string

	Category string

	Damage          float64
	DamageEnd       float64
	DropoffStart    float64
	DropoffEnd      float64
	FireRate        float64
	Pellets         float64
	SpreadHip       float64
	SpreadAim       float64
	RecoilHip       float64
	RecoilAim       float64
	TimeToAim       float64
	ReloadTime      float64
	MagazineSize    float64
	MovementSpeed   float64
	Health          float64
	DetectionRadius float64
	Burst           float64
	DPM             float64
	DPS             float64
	TTKMinutes      float64
	TTKSeconds      float64
}
