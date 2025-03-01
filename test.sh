#!/bin/bash

# Test script for @voltzy/db-export

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing @voltzy/db-export installation...${NC}"

# Check if the command is available
if ! command -v db-export &> /dev/null; then
    echo -e "${RED}Error: db-export command not found.${NC}"
    echo "Please install the package with:"
    echo "  npm install -g @voltzy/db-export"
    exit 1
fi

# Check the version
echo -e "${YELLOW}Checking version:${NC}"
db-export --version

# Check help output
echo -e "\n${YELLOW}Checking help:${NC}"
db-export --help

echo -e "\n${GREEN}Installation test completed successfully!${NC}"
echo "The db-export command is properly installed and available." 