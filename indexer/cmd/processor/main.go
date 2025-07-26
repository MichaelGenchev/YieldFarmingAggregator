package main

import (
	"context"
	"log"
	"math/big"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	ARBITRUM_RPC        = "http://127.0.0.1:8545"
	ABIFilePath         = "strategyVault.json"
	CONTRACT_HEX_ADDRESS = "0x949CA27A2E19A3d7c37eaFEC791750B685798123"
)

var (
	DepositEventSig       = crypto.Keccak256Hash([]byte("Deposit(address,address,uint256,uint256)"))
	WithdrawEventSig      = crypto.Keccak256Hash([]byte("Withdraw(address,address,address,uint256,uint256)"))
	FeesCollectedEventSig = crypto.Keccak256Hash([]byte("FeesCollected(uint256)"))
	PausedEventSig        = crypto.Keccak256Hash([]byte("Paused()"))
)

func startListening(ctx context.Context) {
	client, err := ethclient.Dial(ARBITRUM_RPC)
	if err != nil {
		log.Fatalf("dialing eth client: %w", err)
	}
	defer client.Close()

	chainID, err := client.ChainID(ctx)
	if err != nil {
		log.Fatalf("getting chain ID: %w", err)
	}
	log.Printf("Connected to chain: %s", chainID.String())

	abiData, err := os.ReadFile(ABIFilePath)
	if err != nil {
		log.Fatalf("reading ABI file %s: %v", ABIFilePath, err)
	}
	log.Printf("Loaded ABI from %s", ABIFilePath)

	contractABI, err := abi.JSON(strings.NewReader(string(abiData)))
	if err != nil {
		log.Fatalf("parsing ABI: %v", err)
	}
	log.Printf("Parsed ABI successfully")

	contractAddress := common.HexToAddress(CONTRACT_HEX_ADDRESS)
	lastBlock := big.NewInt(0)

	for {
		select {
		case <-ctx.Done():
			log.Println("Stopping listener")
			return
		default:
			latestBlock, err := client.BlockNumber(ctx)
			if err != nil {
				log.Printf("Failed to get block number: %v", err)
				time.Sleep(2 * time.Second)
				continue
			}
			log.Printf("Polling blocks from %d to %d", lastBlock.Uint64(), latestBlock)

			from := latestBlock - 499
			to := latestBlock
			if to-from > 499 {
				to = from + 499
			}

			query := ethereum.FilterQuery{
				FromBlock: big.NewInt(int64(from)),
				ToBlock:   big.NewInt(int64(to)),
				Addresses: []common.Address{contractAddress},
				Topics:    [][]common.Hash{{DepositEventSig, WithdrawEventSig, FeesCollectedEventSig, PausedEventSig}},
			}

			logs, err := client.FilterLogs(ctx, query)
			if err != nil {
				log.Printf("Failed to filter logs: %v", err)
				time.Sleep(2 * time.Second)
				continue
			}
			if len(logs) == 0 {
				log.Printf("No logs found in block range %d to %d", from, to)
			}

			for _, vLog := range logs {
				log.Printf("Processing log: Tx=%s, Block=%d", vLog.TxHash.Hex(), vLog.BlockNumber)
				switch vLog.Topics[0] {
				case PausedEventSig:
					log.Printf("Paused: Tx=%s, Block=%d, Time=%s", vLog.TxHash.Hex(), vLog.BlockNumber, time.Now().Format(time.RFC3339))
				case DepositEventSig:
					event := struct {
						Assets *big.Int
						Shares *big.Int
					}{}
					if err := contractABI.UnpackIntoInterface(&event, "Deposit", vLog.Data); err != nil {
						log.Printf("Unpacking Deposit: %v", err)
						continue
					}
					caller := common.BytesToAddress(vLog.Topics[1].Bytes())
					receiver := common.BytesToAddress(vLog.Topics[2].Bytes())
					log.Printf("Deposit: Tx=%s, Caller=%s, Receiver=%s, Assets=%s, Shares=%s, Block=%d, Time=%s",
						vLog.TxHash.Hex(), caller.Hex(), receiver.Hex(), event.Assets.String(), event.Shares.String(), vLog.BlockNumber, time.Now().Format(time.RFC3339))
				case WithdrawEventSig:
					event := struct {
						Assets *big.Int
						Shares *big.Int
					}{}
					if err := contractABI.UnpackIntoInterface(&event, "Withdraw", vLog.Data); err != nil {
						log.Printf("Unpacking Withdraw: %v", err)
						continue
					}
					caller := common.BytesToAddress(vLog.Topics[1].Bytes())
					receiver := common.BytesToAddress(vLog.Topics[2].Bytes())
					owner := common.BytesToAddress(vLog.Topics[3].Bytes())
					log.Printf("Withdraw: Tx=%s, Caller=%s, Receiver=%s, Owner=%s, Assets=%s, Shares=%s, Block=%d, Time=%s",
						vLog.TxHash.Hex(), caller.Hex(), receiver.Hex(), owner.Hex(), event.Assets.String(), event.Shares.String(), vLog.BlockNumber, time.Now().Format(time.RFC3339))
				case FeesCollectedEventSig:
					event := struct {
						Amount *big.Int
					}{}
					if err := contractABI.UnpackIntoInterface(&event, "FeesCollected", vLog.Data); err != nil {
						log.Printf("Unpacking FeesCollected: %v", err)
						continue
					}
					log.Printf("FeesCollected: Tx=%s, Amount=%s, Block=%d, Time=%s",
						vLog.TxHash.Hex(), event.Amount.String(), vLog.BlockNumber, time.Now().Format(time.RFC3339))
				default:
					log.Printf("Unknown event with topic: %s", vLog.Topics[0].Hex())
				}
			}

			lastBlock.SetUint64(to + 1)
			time.Sleep(3 * time.Second)
		}
	}
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("Received shutdown signal")
		cancel()
	}()

	startListening(ctx)
}