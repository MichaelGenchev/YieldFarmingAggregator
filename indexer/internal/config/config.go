// internal/config/config.go
package config

import (
	"fmt"
	"github.com/spf13/viper"
)

type Config struct {
	Server       ServerConfig   `yaml:"server" mapstructure:"server"`
	Database     DatabaseConfig `yaml:"database" mapstructure:"database"`
	MessageQueue MessageQConfig `yaml:"message_queue" mapstructure:"message_queue"`
	Chains       []ChainConfig  `yaml:"chains" mapstructure:"chains"`
}

type ServerConfig struct {
	ApiPort string `yaml:"api_port" mapstructure:"api_port"`
}

type DatabaseConfig struct {
	PostgresDSN string `yaml:"postgres_dsn" mapstructure:"postgres_dsn"`
	RedisAddr   string `yaml:"redis_addr" mapstructure:"redis_addr"`
}

type MessageQConfig struct {
	NatsURL string `yaml:"nats_url" mapstructure:"nats_url"`
}

type ChainConfig struct {
	Name            string           `yaml:"name" mapstructure:"name"`
	Key             string           `yaml:"key" mapstructure:"key"`
	ChainID         int              `yaml:"chain_id" mapstructure:"chain_id"`
	Enabled         bool             `yaml:"enabled" mapstructure:"enabled"`
	RpcWsEndpoint   string           `yaml:"rpc_ws_endpoint" mapstructure:"rpc_ws_endpoint"`
	RpcHttpEndpoint string           `yaml:"rpc_http_endpoint" mapstructure:"rpc_http_endpoint"`
	StartBlock      uint64           `yaml:"start_block" mapstructure:"start_block"`
	Protocols       []ProtocolConfig `yaml:"protocols" mapstructure:"protocols"`
}

type ProtocolConfig struct {
	Name         string          `yaml:"name" mapstructure:"name"`
	VaultAddress string          `yaml:"vault_address" mapstructure:"vault_address"`
	Adapters     []AdapterConfig `yaml:"adapters" mapstructure:"adapters"`
}

type AdapterConfig struct {
	Name    string `yaml:"name" mapstructure:"name"`
	Address string `yaml:"address" mapstructure:"address"`
	AbiPath string `yaml:"abi_path" mapstructure:"abi_path"`
}

// LoadConfig function remains the same
func LoadConfig(path string) (config Config, err error) {
	viper.AddConfigPath(path)
	viper.SetConfigName("config")
	viper.SetConfigType("yml")

	viper.AutomaticEnv()

	err = viper.ReadInConfig()
	if err != nil {
		return Config{}, fmt.Errorf("fatal error config file: %w", err)
	}

	err = viper.Unmarshal(&config)
	return
}