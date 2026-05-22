package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

func main() {
	// Test actual API response structure
	url := "https://api.datajockey.io/v0/company/financials?apikey=f87d23e621e7d523d7b2df3092e66d3f8459271006ab11ee9c59&ticker=AAPL"
	
	resp, err := http.Get(url)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}
	defer resp.Body.Close()
	
	body, _ := io.ReadAll(resp.Body)
	
	// Try to parse as generic JSON to see structure
	var data map[string]interface{}
	if err := json.Unmarshal(body, &data); err != nil {
		fmt.Printf("Error parsing JSON: %v\n", err)
		fmt.Printf("Response: %s\n", string(body))
		return
	}
	
	fmt.Println("=== Full API Response Structure ===")
	prettyJSON, _ := json.MarshalIndent(data, "", "  ")
	fmt.Println(string(prettyJSON))
	
	// Check financial_data structure
	if financialData, ok := data["financial_data"].(map[string]interface{}); ok {
		fmt.Println("\n=== Financial Data Keys ===")
		for key := range financialData {
			fmt.Printf("- %s\n", key)
		}
		
		if annual, ok := financialData["annual"].(map[string]interface{}); ok {
			fmt.Println("\n=== Annual Data Keys ===")
			for key := range annual {
				fmt.Printf("- %s\n", key)
			}
		}
	}
}

