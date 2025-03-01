#!/bin/bash

# Installation script for @voltzy/db-export

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Installing @voltzy/db-export...${NC}"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is not installed.${NC}"
    echo "Please install Node.js 18 or higher from https://nodejs.org/"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | cut -d 'v' -f 2)
NODE_MAJOR=$(echo $NODE_VERSION | cut -d '.' -f 1)

if [ $NODE_MAJOR -lt 18 ]; then
    echo -e "${RED}Error: Node.js 18 or higher is required.${NC}"
    echo "Current version: $NODE_VERSION"
    echo "Please upgrade Node.js from https://nodejs.org/"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo -e "${RED}Error: npm is not installed.${NC}"
    echo "Please install npm (it usually comes with Node.js)"
    exit 1
fi

# Install the package globally
echo "Installing package globally..."
npm install -g .

# Check if installation was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Installation successful!${NC}"
    echo -e "You can now use the ${YELLOW}db-export${NC} command from anywhere."
    echo ""
    echo "Example usage:"
    echo "  db-export --help"
    echo "  db-export --output ./my-database-export"
    echo ""
    echo -e "${YELLOW}Note:${NC} You may need to configure your database connection in a .env file:"
    echo "SUPABASE_URL=https://your-project.supabase.co"
    echo "SUPABASE_SERVICE_KEY=your-service-role-key"
else
    echo -e "${RED}Installation failed.${NC}"
    echo "Please try again or install manually with:"
    echo "npm install -g ."
fi 