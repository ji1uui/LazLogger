FPC ?= fpc
BUILD_DIR := build
UNIT_DIR := $(BUILD_DIR)/units
SOURCE_PATHS := -Fu./src/domain -Fu./src/application -Fu./src/infrastructure \
	-Fu./src/presentation
FPC_FLAGS := -Mobjfpc -Sh -Fu. $(SOURCE_PATHS) -FU$(UNIT_DIR)

.PHONY: all test test-tools run benchmark benchmark-memory verify-demo clean check-fpc

all: $(BUILD_DIR)/zlog-demo

check-fpc:
	@command -v $(FPC) >/dev/null 2>&1 || { \
		echo "Free Pascal compiler not found: $(FPC)" >&2; exit 127; \
	}

$(BUILD_DIR) $(UNIT_DIR):
	mkdir -p $@

$(BUILD_DIR)/zlog-demo: check-fpc | $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -o$@ app/zlog.lpr

$(BUILD_DIR)/test-runner: check-fpc | $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -o$@ tests/unit/test_runner.lpr

$(BUILD_DIR)/journal-benchmark: check-fpc | $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -O2 -o$@ tests/benchmark/journal_benchmark.lpr

$(BUILD_DIR)/repository-benchmark: check-fpc | $(BUILD_DIR) $(UNIT_DIR)
	$(FPC) $(FPC_FLAGS) -O2 -o$@ tests/benchmark/repository_benchmark.lpr

test: $(BUILD_DIR)/test-runner
	./$(BUILD_DIR)/test-runner

test-tools:
	python3 -m unittest discover -s tests/tools -p 'test_*.py' -v

run: $(BUILD_DIR)/zlog-demo
	./$(BUILD_DIR)/zlog-demo

benchmark: $(BUILD_DIR)/journal-benchmark
	./$(BUILD_DIR)/journal-benchmark 200

benchmark-memory: $(BUILD_DIR)/repository-benchmark
	./$(BUILD_DIR)/repository-benchmark

verify-demo:
	python3 tools/verify_journal.py --expect-count 2 --require-complete-tail zlog-demo.journal

clean:
	rm -rf $(BUILD_DIR)
