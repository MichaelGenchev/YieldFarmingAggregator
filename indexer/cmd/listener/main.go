package main

import (
	"fmt"
	"log"
	"os"

	"github.com/MichaelGenchev/YieldFarmingAggregator/indexer/internal/config"
)

func main() {
	// === STEP 1: PRINT THE CURRENT WORKING DIRECTORY ===
	wd, err := os.Getwd()
	if err != nil {
		log.Fatalf("Could not get current working directory: %v", err)
	}
	fmt.Printf(">>> Current Working Directory: %s\n", wd)

	// === STEP 2: CHECK IF config.yml EXISTS HERE ===
	configPath := "config.yml"
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		log.Fatalf(">>> CRITICAL: config.yml does not exist in the current directory!")
	} else {
		fmt.Println(">>> SUCCESS: config.yml found.")
	}
	
	fmt.Println("-----------------------------------------")
	fmt.Println("Attempting to load config...")

	// === STEP 3: LOAD CONFIG WITH DETAILED ERROR LOGGING ===
	cfg, err := config.LoadConfig(".")
	if err != nil {
		// This is the most important line. It will print the exact Viper error.
		log.Fatalf(">>> CRITICAL: Failed to load config: %v", err)
	}

	fmt.Println("Config loaded successfully. Printing values...")
	fmt.Println("-----------------------------------------")

	// Your original print logic
	for _, chain := range cfg.Chains {
		fmt.Printf("Chain Name: %s, Chain ID: %d, Start Block: %d\n", chain.Name, chain.ChainID, chain.StartBlock)
		fmt.Printf("  RPC HTTP: %s\n", chain.RpcHttpEndpoint)
		// ... add any other fields you want to check
	}
}
