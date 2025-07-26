package chain

import (
	"github.com/MichaelGenchev/YieldFarmingAggregator/indexer/internal/config"
	"github.com/ethereum/go-ethereum/ethclient"
)


type IChainConnector interface {
	GetClient() *ethclient.Client
}

type ChainConnector struct {
	chainConfig config.ChainConfig
	client *ethclient.Client
}



func NewChainConnector(chainConfig, client *ethclient.Client) *ChainConnector {
	return &ChainConnector{
		chainConfig: chainConfig,
		client: client,
	}
}

