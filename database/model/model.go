package model

import "encoding/json"

type Setting struct {
	Id    uint   `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Key   string `json:"key" form:"key"`
	Value string `json:"value" form:"value"`
}

type Tls struct {
	Id     uint            `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Name   string          `json:"name" form:"name"`
	Server json.RawMessage `json:"server" form:"server"`
	Client json.RawMessage `json:"client" form:"client"`
}

type User struct {
	Id            uint            `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Username      string          `json:"username" form:"username" gorm:"uniqueIndex"`
	Password      string          `json:"-" form:"password"`
	LastLogins    string          `json:"lastLogin"`
	TOTPSecret    string          `json:"-" gorm:"column:totp_secret"`
	TOTPEnabled   bool            `json:"totpEnabled" gorm:"column:totp_enabled;default:false;not null"`
	RecoveryCodes json.RawMessage `json:"-" gorm:"column:recovery_codes"`
}

type PasskeyCredential struct {
	Id         uint            `json:"id" gorm:"primaryKey;autoIncrement"`
	UserId     uint            `json:"userId" gorm:"index;not null"`
	Name       string          `json:"name"`
	Credential json.RawMessage `json:"-" gorm:"not null"`
	CreatedAt  int64           `json:"createdAt"`
	LastUsedAt int64           `json:"lastUsedAt"`
}

type Client struct {
	Id       uint            `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Enable   bool            `json:"enable" form:"enable"`
	Name     string          `json:"name" form:"name"`
	Config   json.RawMessage `json:"config,omitempty" form:"config"`
	Inbounds json.RawMessage `json:"inbounds" form:"inbounds"`
	Links    json.RawMessage `json:"links,omitempty" form:"links"`
	Volume   int64           `json:"volume" form:"volume"`
	Expiry   int64           `json:"expiry" form:"expiry"`
	Down     int64           `json:"down" form:"down"`
	Up       int64           `json:"up" form:"up"`
	Desc     string          `json:"desc" form:"desc"`
	Group    string          `json:"group" form:"group"`

	// Delay start and periodic reset
	DelayStart bool  `json:"delayStart" form:"delayStart" gorm:"default:false;not null"`
	AutoReset  bool  `json:"autoReset" form:"autoReset" gorm:"default:false;not null"`
	ResetDays  int   `json:"resetDays" form:"resetDays" gorm:"default:0;not null"`
	NextReset  int64 `json:"nextReset" form:"nextReset" gorm:"default:0;not null"`
	TotalUp    int64 `json:"totalUp" form:"totalUp" gorm:"default:0;not null"`
	TotalDown  int64 `json:"totalDown" form:"totalDown" gorm:"default:0;not null"`
}

type Stats struct {
	Id        uint64 `json:"id" gorm:"primaryKey;autoIncrement"`
	DateTime  int64  `json:"dateTime" gorm:"index:idx_stats_resource_tag_time,priority:3;index:idx_stats_time"`
	Resource  string `json:"resource" gorm:"index:idx_stats_resource_tag_time,priority:1"`
	Tag       string `json:"tag" gorm:"index:idx_stats_resource_tag_time,priority:2"`
	Direction bool   `json:"direction"`
	Traffic   int64  `json:"traffic"`
}

type Changes struct {
	Id       uint64          `json:"id" gorm:"primaryKey;autoIncrement"`
	DateTime int64           `json:"dateTime" gorm:"index:idx_changes_actor_time,priority:2;index:idx_changes_key_time,priority:2;index:idx_changes_time"`
	Actor    string          `json:"actor" gorm:"index:idx_changes_actor_time,priority:1"`
	Key      string          `json:"key" gorm:"index:idx_changes_key_time,priority:1"`
	Action   string          `json:"action"`
	Obj      json.RawMessage `json:"obj"`
}

type Tokens struct {
	Id     uint   `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Desc   string `json:"desc" form:"desc"`
	Token  string `json:"token" form:"token"`
	Expiry int64  `json:"expiry" form:"expiry"`
	UserId uint   `json:"userId" form:"userId"`
	User   *User  `json:"user" gorm:"foreignKey:UserId;references:Id"`
}
