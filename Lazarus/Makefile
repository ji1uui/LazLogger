FPC ?= fpc
BUILD_DIR := build
UNIT_DIR := $(BUILD_DIR)/units
SOURCE_PATHS := -Fu./src/domain -Fu./src/application -Fu./src/infrastructure
FPC_FLAGS := -Mobjfpc -Sh -Fu. $(SOURCE_PATHS) -FU$(UNIT_DIR)
CORE_SOURCES := $(shell find src -type f -name '*.pas')

.PHONY: all test run clean check-fpc

all: $(BUILD_DIR)/zlog-demo

check-fpc:
	@command -v $(FPC) >/dev/null 2>&1 || { \
		echo "Free Pascal compiler not found: $(FPC)" >&2; exit 127; \
	}

$(BUILD_DIR) $(UNIT_DIR):
	mkdir -p $@

$(BUILD_DIR)/zlog-demo: app/zlog.lpr $(CORE_SOURCES) | check-fpc $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -o$@ app/zlog.lpr

$(BUILD_DIR)/test-runner: tests/unit/test_runner.lpr $(CORE_SOURCES) | check-fpc $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -o$@ tests/unit/test_runner.lpr

test: $(BUILD_DIR)/test-runner
	./$(BUILD_DIR)/test-runner

run: $(BUILD_DIR)/zlog-demo
	./$(BUILD_DIR)/zlog-demo

clean:
	rm -rf $(BUILD_DIR)
