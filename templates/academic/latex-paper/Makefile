# Modern LaTeX Academic Paper Makefile
# Optimized for LuaLaTeX + Biber workflow

# Configuration
PAPER_NAME := paper
MAIN_TEX := $(PAPER_NAME).tex
MAIN_PDF := $(PAPER_NAME).pdf
BIB_FILE := references.bib

# LaTeX engine and options
LATEX_ENGINE := lualatex
LATEX_OPTIONS := -synctex=1 -interaction=nonstopmode -file-line-error -output-directory=build

# Bibliography processor
BIB_PROCESSOR := biber

# Build directory
BUILD_DIR := build

# Source files
TEX_SOURCES := $(wildcard *.tex) $(wildcard sections/*.tex) $(wildcard chapters/*.tex)
BIB_SOURCES := $(wildcard *.bib)
FIGURE_SOURCES := $(wildcard figures/*) $(wildcard images/*)

# Default target
.PHONY: all
all: $(MAIN_PDF)

# Setup project structure
.PHONY: setup
setup:
	@echo "📝 Setting up LaTeX academic paper structure..."
	@mkdir -p build sections figures images
	@if [ ! -f $(MAIN_TEX) ]; then \
		echo "Creating main LaTeX file: $(MAIN_TEX)"; \
		cp template-paper.tex $(MAIN_TEX); \
	fi
	@if [ ! -f $(BIB_FILE) ]; then \
		echo "Creating bibliography file: $(BIB_FILE)"; \
		touch $(BIB_FILE); \
	fi
	@if [ ! -f .latexmkrc ]; then \
		echo "Creating .latexmkrc configuration"; \
		cp template.latexmkrc .latexmkrc; \
	fi
	@echo "✅ Project structure ready!"

# Build PDF (main target)
$(MAIN_PDF): $(TEX_SOURCES) $(BIB_SOURCES) $(FIGURE_SOURCES) | $(BUILD_DIR)
	@echo "🔨 Building $(MAIN_PDF)..."
	$(LATEX_ENGINE) $(LATEX_OPTIONS) $(MAIN_TEX)
	@if [ -f $(BIB_FILE) ] && [ -s $(BIB_FILE) ]; then \
		echo "📚 Processing bibliography..."; \
		$(BIB_PROCESSOR) $(BUILD_DIR)/$(PAPER_NAME); \
		$(LATEX_ENGINE) $(LATEX_OPTIONS) $(MAIN_TEX); \
		$(LATEX_ENGINE) $(LATEX_OPTIONS) $(MAIN_TEX); \
	fi
	@if [ -f $(BUILD_DIR)/$(MAIN_PDF) ]; then \
		cp $(BUILD_DIR)/$(MAIN_PDF) .; \
		echo "✅ PDF built successfully: $(MAIN_PDF)"; \
	else \
		echo "❌ PDF build failed"; \
		exit 1; \
	fi

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Fast build (skip bibliography)
.PHONY: fast
fast: | $(BUILD_DIR)
	@echo "⚡ Fast build (no bibliography)..."
	$(LATEX_ENGINE) $(LATEX_OPTIONS) $(MAIN_TEX)
	@cp $(BUILD_DIR)/$(MAIN_PDF) . 2>/dev/null || true

# Continuous build with file watching
.PHONY: watch
watch:
	@echo "👀 Starting continuous build (Ctrl+C to stop)..."
	@if command -v latexmk >/dev/null 2>&1; then \
		latexmk -$(LATEX_ENGINE) -pvc -file-line-error -interaction=nonstopmode $(MAIN_TEX); \
	else \
		echo "⚠️  latexmk not found, falling back to basic watch..."; \
		while true; do \
			make fast; \
			sleep 2; \
		done; \
	fi

# Open PDF in viewer
.PHONY: view
view: $(MAIN_PDF)
	@if command -v zathura >/dev/null 2>&1; then \
		echo "📄 Opening PDF in Zathura..."; \
		zathura $(MAIN_PDF) & \
	elif command -v open >/dev/null 2>&1; then \
		echo "📄 Opening PDF with system viewer..."; \
		open $(MAIN_PDF); \
	else \
		echo "📄 PDF ready: $(MAIN_PDF)"; \
	fi

# Word count
.PHONY: wordcount
wordcount: $(MAIN_TEX)
	@echo "📊 Word count analysis:"
	@if command -v texcount >/dev/null 2>&1; then \
		texcount -inc -brief $(MAIN_TEX); \
	else \
		echo "⚠️  texcount not available, using basic count:"; \
		pdftotext $(MAIN_PDF) - | wc -w; \
	fi

# Spell check
.PHONY: spell
spell: $(TEX_SOURCES)
	@echo "🔍 Spell checking..."
	@for file in $(TEX_SOURCES); do \
		echo "Checking $$file:"; \
		aspell check $$file; \
	done

# Bibliography validation
.PHONY: bibcheck
bibcheck: $(BIB_FILE)
	@if [ -f $(BIB_FILE) ] && [ -s $(BIB_FILE) ]; then \
		echo "📚 Validating bibliography..."; \
		$(BIB_PROCESSOR) --tool --validate-datamodel $(BIB_FILE); \
	else \
		echo "⚠️  No bibliography file found"; \
	fi

# Clean auxiliary files
.PHONY: clean
clean:
	@echo "🧹 Cleaning auxiliary files..."
	@rm -f *.aux *.bbl *.blg *.idx *.ind *.lof *.lot *.out *.toc
	@rm -f *.acn *.acr *.alg *.glg *.glo *.gls *.ist *.fls
	@rm -f *.log *.fdb_latexmk *.run.xml *.bcf *.nav *.snm *.vrb
	@rm -f *.synctex.gz *.figlist *.makefile *.figlist
	@rm -rf $(BUILD_DIR)
	@echo "✅ Cleanup complete"

# Clean everything including PDF
.PHONY: distclean
distclean: clean
	@echo "🧹 Deep cleaning (including PDF)..."
	@rm -f $(MAIN_PDF)
	@rm -rf .texlive .texmf
	@echo "✅ Deep cleanup complete"

# Archive project for submission
.PHONY: archive
archive: clean $(MAIN_PDF)
	@echo "📦 Creating submission archive..."
	@tar -czf $(PAPER_NAME)-$(shell date +%Y%m%d).tar.gz \
		$(MAIN_TEX) $(BIB_SOURCES) $(TEX_SOURCES) $(FIGURE_SOURCES) $(MAIN_PDF) \
		Makefile .latexmkrc README.md 2>/dev/null || true
	@echo "✅ Archive created: $(PAPER_NAME)-$(shell date +%Y%m%d).tar.gz"

# Development help
.PHONY: help
help:
	@echo "📝 LaTeX Academic Paper Makefile"
	@echo "================================"
	@echo ""
	@echo "🎯 Main targets:"
	@echo "  setup      Initialize project structure"
	@echo "  all        Build complete PDF (default)"
	@echo "  fast       Quick build without bibliography"
	@echo "  watch      Continuous build with file watching"
	@echo "  view       Open PDF in viewer"
	@echo ""
	@echo "🔧 Utilities:"
	@echo "  wordcount  Count words in document"
	@echo "  spell      Run spell checker"
	@echo "  bibcheck   Validate bibliography"
	@echo ""
	@echo "🧹 Maintenance:"
	@echo "  clean      Remove auxiliary files"
	@echo "  distclean  Remove all generated files"
	@echo "  archive    Create submission archive"
	@echo ""
	@echo "📋 Configuration:"
	@echo "  PAPER_NAME = $(PAPER_NAME)"
	@echo "  LATEX_ENGINE = $(LATEX_ENGINE)"
	@echo "  BIB_PROCESSOR = $(BIB_PROCESSOR)"

# Debug information
.PHONY: debug
debug:
	@echo "🐛 Debug Information"
	@echo "==================="
	@echo "Paper name: $(PAPER_NAME)"
	@echo "Main TeX: $(MAIN_TEX)"
	@echo "Main PDF: $(MAIN_PDF)"
	@echo "LaTeX engine: $(LATEX_ENGINE)"
	@echo "Bibliography processor: $(BIB_PROCESSOR)"
	@echo "Build directory: $(BUILD_DIR)"
	@echo ""
	@echo "📁 Source files:"
	@echo "TEX sources: $(TEX_SOURCES)"
	@echo "BIB sources: $(BIB_SOURCES)"
	@echo "Figure sources: $(FIGURE_SOURCES)"
	@echo ""
	@echo "🔧 Tool availability:"
	@echo -n "LaTeX: "; command -v $(LATEX_ENGINE) >/dev/null && echo "✅ Available" || echo "❌ Missing"
	@echo -n "Biber: "; command -v $(BIB_PROCESSOR) >/dev/null && echo "✅ Available" || echo "❌ Missing"
	@echo -n "Pandoc: "; command -v pandoc >/dev/null && echo "✅ Available" || echo "❌ Missing"
	@echo -n "Zathura: "; command -v zathura >/dev/null && echo "✅ Available" || echo "❌ Missing"