#!/bin/bash

# Build script for CI/CD pipelines
set -e

echo "🔨 Building Prompt Injection Detector..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Version from git tag or default
VERSION=${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}

echo -e "${YELLOW}Version: ${VERSION}${NC}"

# Step 1: Lint
echo -e "\n${YELLOW}Step 1: Linting code...${NC}"
if command -v flake8 &> /dev/null; then
    flake8 *.py || echo -e "${YELLOW}Warning: Linting issues found${NC}"
else
    echo -e "${YELLOW}Skipping linting (flake8 not installed)${NC}"
fi

# Step 2: Run tests
echo -e "\n${YELLOW}Step 2: Running tests...${NC}"
if command -v pytest &> /dev/null; then
    pytest test_detector.py -v --tb=short || {
        echo -e "${RED}✗ Tests failed${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Tests passed${NC}"
else
    echo -e "${RED}Error: pytest not installed${NC}"
    exit 1
fi

# Step 3: Security check
echo -e "\n${YELLOW}Step 3: Security scanning...${NC}"
if command -v bandit &> /dev/null; then
    bandit -r *.py -ll || echo -e "${YELLOW}Warning: Security issues found${NC}"
else
    echo -e "${YELLOW}Skipping security scan (bandit not installed)${NC}"
fi

# Step 4: Build Docker image (if Docker available)
if command -v docker &> /dev/null && [ -f Dockerfile ]; then
    echo -e "\n${YELLOW}Step 4: Building Docker image...${NC}"
    docker build -t prompt-injection-detector:${VERSION} . || {
        echo -e "${RED}✗ Docker build failed${NC}"
        exit 1
    }
    docker tag prompt-injection-detector:${VERSION} prompt-injection-detector:latest
    echo -e "${GREEN}✓ Docker image built${NC}"
else
    echo -e "${YELLOW}Skipping Docker build${NC}"
fi

# Step 5: Run integration tests
echo -e "\n${YELLOW}Step 5: Running integration tests...${NC}"
python prompt_injection_detector.py || {
    echo -e "${RED}✗ Integration test failed${NC}"
    exit 1
}
echo -e "${GREEN}✓ Integration tests passed${NC}"

echo -e "\n${GREEN}✓ Build completed successfully!${NC}"
echo -e "${GREEN}Version: ${VERSION}${NC}"
