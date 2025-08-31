# Simple Lambda Setup Makefile for Python 3.13
# Creates zip files for manual AWS upload

# Configuration
PYTHON_VERSION := 3.13


BUILD_DIR := build
PYTHON_DIR := $(BUILD_DIR)/python
BIN_DIR := $(BUILD_DIR)/bin
DIST_DIR := dist


FFMPEG_LAYER_ZIP := $(DIST_DIR)/ffmpeg-layer.zip
PYTHON_LAYER_ZIP := $(DIST_DIR)/python-layer.zip
COMBINED_LAYER_ZIP := $(DIST_DIR)/lambda-layer.zip

# Colors for output
GREEN := \033[0;32m
BLUE := \033[0;34m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: all clean python-layer ffmpeg-layer combined-layer clean-build clean-dist help


all: combined-layer


setup:
	@echo "$(BLUE)🔧 Setting up build environment...$(NC)"
	@mkdir -p $(BUILD_DIR) $(DIST_DIR) $(PYTHON_DIR) $(BIN_DIR)
	@echo "$(GREEN)✅ Environment ready!$(NC)"

install-uv:
	@echo "$(BLUE)⚡ Checking for uv...$(NC)"
	@if ! command -v uv &> /dev/null; then \
		echo "Installing uv..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	else \
		echo "uv already installed: $$(uv --version)"; \
	fi

## Install Python dependencies using uv
python-deps: install-uv
	@echo "$(BLUE)🐍 Installing Python dependencies with uv...$(NC)"
	
	@if [ -f "pyproject.toml" ]; then \
		echo "Installing from pyproject.toml..."; \
		uv pip install . --target $(PYTHON_DIR); \
	elif [ -f "requirements.txt" ]; then \
		echo "Installing from requirements.txt..."; \
		uv pip install --target $(PYTHON_DIR) -r requirements.txt; \
	else \
		echo "$(YELLOW)⚠️  No pyproject.toml or requirements.txt found$(NC)"; \
		echo "$(YELLOW)Creating sample requirements.txt...$(NC)"; \
		echo "requests>=2.31.0" > requirements.txt; \
		echo "boto3>=1.34.0" >> requirements.txt; \
		uv pip install --target $(PYTHON_DIR) -r requirements.txt; \
	fi
	
	# Clean up unnecessary files
	@find $(PYTHON_DIR) -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find $(PYTHON_DIR) -name "*.pyc" -delete 2>/dev/null || true
	@find $(PYTHON_DIR) -name "*.pyo" -delete 2>/dev/null || true
	
	@echo "$(GREEN)✅ Python dependencies installed!$(NC)"


## Download and setup FFmpeg binary only
ffmpeg-binary:
	@echo "$(BLUE)🎬 Downloading FFmpeg binary...$(NC)"
	
	@echo "Attempting to download FFmpeg static binary..."
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)
	@if curl -L -f https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz -o $(BUILD_DIR)/ffmpeg.tar.xz; then \
		echo "Extracting FFmpeg binary..."; \
		tar -xf $(BUILD_DIR)/ffmpeg.tar.xz -C $(BUILD_DIR); \
		FFMPEG_DIR=$$(find $(BUILD_DIR) -name "ffmpeg-*-amd64-static" -type d | head -1); \
		if [ -n "$$FFMPEG_DIR" ] && [ -f "$$FFMPEG_DIR/ffmpeg" ]; then \
			cp "$$FFMPEG_DIR/ffmpeg" $(BIN_DIR)/; \
			echo "✅ FFmpeg binary extracted successfully!"; \
		else \
			echo "❌ FFmpeg binary not found in archive"; \
		fi; \
	else \
		echo "$(RED)❌ Failed to download FFmpeg binary.$(NC)"; \
		echo "$(YELLOW)⚠️  Creating placeholder. You can add FFmpeg manually later.$(NC)"; \
		mkdir -p $(BIN_DIR); \
		echo "# FFmpeg binary - add manually" > $(BIN_DIR)/README.md; \
	fi
	
	@chmod +x $(BIN_DIR)/ffmpeg 2>/dev/null || echo "FFmpeg binary not available"
	@[ -f "$(BIN_DIR)/ffmpeg" ] && echo "$(GREEN)✅ FFmpeg binary ready!$(NC)" || echo "$(YELLOW)⚠️  FFmpeg binary not available"

## Create Python dependencies layer zip
python-layer: setup python-deps
	@echo "$(BLUE)📦 Creating Python dependencies layer...$(NC)"
	@cd $(BUILD_DIR) && zip -r ../$(PYTHON_LAYER_ZIP) python/
	@echo "$(GREEN)✅ Python layer created: $(PYTHON_LAYER_ZIP)$(NC)"
	@echo "Size: $$(du -h $(PYTHON_LAYER_ZIP) | cut -f1)"

## Create FFmpeg layer zip
ffmpeg-layer: setup ffmpeg-binary
	@echo "$(BLUE)📦 Creating FFmpeg layer...$(NC)"
	@cd $(BUILD_DIR) && zip -r ../$(FFMPEG_LAYER_ZIP) bin/
	@echo "$(GREEN)✅ FFmpeg layer created: $(FFMPEG_LAYER_ZIP)$(NC)"
	@echo "Size: $$(du -h $(FFMPEG_LAYER_ZIP) | cut -f1)"



## Create combined layer (FFmpeg + Python dependencies + lambda function)
combined-layer: setup python-deps ffmpeg-binary
	@echo "$(BLUE)📦 Checking for lambda_function.py...$(NC)"
	@if [ ! -f "lambda_function.py" ]; then \
		echo "$(RED)❌ lambda_function.py not found in current directory!$(NC)"; \
		exit 1; \
	fi
	@cp lambda_function.py $(BUILD_DIR)/
	@echo "$(GREEN)✅ lambda_function.py copied to build!$(NC)"

	@echo "$(BLUE)📦 Creating combined Lambda layer...$(NC)"
	@cd $(BUILD_DIR) && zip -r ../$(COMBINED_LAYER_ZIP) bin/ python/ lambda_function.py
	@echo "$(GREEN)✅ Combined layer created: $(COMBINED_LAYER_ZIP)$(NC)"
	@echo "Size: $$(du -h $(COMBINED_LAYER_ZIP) | cut -f1)"
	@echo "Files: $$(find $(BUILD_DIR) -type f | wc -l)"

## Clean build directories
clean-build:
	@echo "$(YELLOW)🧹 Cleaning build directories...$(NC)"
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✅ Build directories cleaned!$(NC)"

## Clean distribution files
clean-dist:
	@echo "$(YELLOW)🧹 Cleaning distribution files...$(NC)"
	@rm -rf $(DIST_DIR)
	@echo "$(GREEN)✅ Distribution files cleaned!$(NC)"

## Clean everything
clean: clean-build clean-dist
	@echo "$(YELLOW)🧹 Cleaning everything...$(NC)"
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "$(GREEN)✅ All cleaned!$(NC)"

## Show help
help:
	@echo "$(BLUE)🎯 Lambda Layer Builder Help$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)make$(NC) or $(GREEN)make combined-layer$(NC)  - Create combined layer (default)"
	@echo "  $(GREEN)make python-layer$(NC)          - Create Python dependencies layer only"
	@echo "  $(GREEN)make ffmpeg-layer$(NC)          - Create FFmpeg layer only"
	@echo "  $(GREEN)make clean$(NC)                 - Clean all build files"
	@echo ""
	@echo "Output files:"
	@echo "  $(COMBINED_LAYER_ZIP)  - Combined layer for manual upload"
	@echo "  $(PYTHON_LAYER_ZIP)    - Python dependencies only"
	@echo "  $(FFMPEG_LAYER_ZIP)    - FFmpeg binary only"

## Default target help
.DEFAULT_GOAL := help