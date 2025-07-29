# 📝 LaTeX Academic Paper Template

Modern LaTeX template for academic paper writing with comprehensive toolchain integration.

## ✨ Features

- **LuaLaTeX Engine** - Unicode support, modern typography, Japanese fonts
- **BibLaTeX + Biber** - Modern bibliography management
- **SyncTeX Integration** - PDF ↔ source synchronization
- **VS Code + Neovim Support** - Editor integration with LSP
- **Automated Build** - Makefile and latexmk integration
- **Modern Layout** - Professional typography and formatting

## 🚀 Quick Start

```bash
# Enter the development environment
nix develop .#templates.academic.latex-paper

# Initialize project structure
make setup

# Build the paper
make build

# Continuous build with file watching
make watch

# View PDF with SyncTeX
make view
```

## 📁 Project Structure

```
paper/
├── paper.tex              # Main LaTeX document
├── references.bib         # Bibliography database
├── sections/              # Document sections (optional)
├── figures/               # Images and diagrams
├── build/                 # Build artifacts
├── Makefile              # Build automation
├── .latexmkrc            # LaTeX build configuration
└── README.md             # This file
```

## 🔧 Available Commands

### Building
- `make build` - Build complete PDF with bibliography
- `make fast` - Quick build without bibliography processing
- `make watch` - Continuous build with file monitoring
- `make view` - Open PDF in viewer (Zathura/system default)

### Utilities
- `make wordcount` - Count words in document
- `make spell` - Run spell checker on LaTeX sources
- `make bibcheck` - Validate bibliography file

### Maintenance
- `make clean` - Remove auxiliary build files
- `make distclean` - Remove all generated files including PDF
- `make archive` - Create submission archive

## 📚 Writing Workflow

### 1. Content Creation
- Edit `paper.tex` for main content
- Add references to `references.bib`
- Place figures in `figures/` directory
- Use `sections/` for large documents

### 2. Bibliography Management
```latex
% In your LaTeX document
\textcite{author2023}        % Author (2023) says...
\parencite{author2023}       % Statement (Author, 2023)
\cite{author2023}            % Author, 2023
```

### 3. Figures and Tables
```latex
% Figure example
\begin{figure}[htbp]
    \centering
    \includegraphics[width=0.8\textwidth]{figures/my-figure.pdf}
    \caption{Figure caption}
    \label{fig:my-figure}
\end{figure}

% Table example  
\begin{table}[htbp]
    \centering
    \caption{Table caption}
    \label{tab:my-table}
    \begin{tabular}{lrr}
        \toprule
        Header 1 & Header 2 & Header 3 \\
        \midrule
        Data & 123 & 456 \\
        \bottomrule
    \end{tabular}
\end{table}
```

## 🎨 Customization

### Document Metadata
Edit the preamble in `paper.tex`:
```latex
\title{Your Paper Title}
\author{Your Name\thanks{Email: your.email@university.edu}}
\date{\today}

% PDF metadata
\hypersetup{
    pdftitle={Your Paper Title},
    pdfauthor={Your Name},
    pdfsubject={Research Topic},
    pdfkeywords={keyword1, keyword2, keyword3}
}
```

### Fonts and Typography
The template uses:
- **English**: Latin Modern (default LaTeX fonts)
- **Japanese**: Noto CJK fonts (automatically configured)
- **Code**: Latin Modern Mono

### Bibliography Style
Currently configured for `authoryear-comp` style. To change:
```latex
\usepackage[
    backend=biber,
    style=numeric,  % or ieee, apa, chicago-authordate, etc.
    sorting=none    % or nyt, ynt, etc.
]{biblatex}
```

## 🔧 Editor Integration

### VS Code
- Install LaTeX Workshop extension
- Use Ctrl+Alt+B to build
- SyncTeX: Ctrl+Click in PDF to jump to source

### Neovim with Vimtex
- `<leader>ll` - Compile document
- `<leader>lv` - View PDF
- `<leader>lc` - Clean auxiliary files
- `<leader>lt` - Toggle table of contents

## 📊 Quality Assurance

### Spell Checking
```bash
make spell                  # Interactive spell check
aspell check paper.tex      # Manual spell check
```

### Word Count
```bash
make wordcount             # LaTeX-aware word count
```

### Bibliography Validation
```bash
make bibcheck              # Validate .bib file
biber --tool --validate-datamodel references.bib
```

## 📦 Submission Preparation

```bash
# Create submission archive
make archive

# This creates: paper-YYYYMMDD.tar.gz containing:
# - All LaTeX source files
# - Bibliography database
# - Figures and images
# - Final PDF
# - Build configuration
```

## 🔍 Troubleshooting

### Common Issues

**Build fails with font errors:**
```bash
# Ensure fonts are available
fc-list | grep -i "noto.*cjk"
```

**Bibliography not appearing:**
```bash
# Check .bib file syntax
make bibcheck

# Manual bibliography build
lualatex paper.tex
biber paper
lualatex paper.tex
lualatex paper.tex
```

**SyncTeX not working:**
- Ensure `-synctex=1` flag is used
- Check PDF viewer supports SyncTeX
- Try different viewer (Zathura recommended)

### Debug Information
```bash
make debug                 # Show configuration and tool availability
```

## 📚 Resources

- [LaTeX Documentation](https://www.latex-project.org/help/documentation/)
- [BibLaTeX Manual](https://ctan.org/pkg/biblatex)
- [LuaLaTeX Guide](https://www.luatex.org/)
- [Academic Writing Best Practices](https://example.edu/writing-guide)

## 🤝 Contributing

1. Fork this template
2. Make improvements
3. Test with different document types
4. Submit pull request

## 📄 License

This template is released under the MIT License. Feel free to use and modify for your academic work.

---

*Happy writing! 📝✨*