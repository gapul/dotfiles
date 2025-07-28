# LaTeX Makefile configuration for modern academic writing
# Optimized for LuaLaTeX + Biber workflow

# Use LuaLaTeX as the primary engine
$pdf_mode = 4;  # 4 = lualatex
$lualatex = 'lualatex %O -synctex=1 -interaction=nonstopmode -file-line-error %S';

# Use Biber for bibliography processing
$biber = 'biber %O --bblencoding=utf8 -u -U --output_safechars %B';
$bibtex_use = 2;  # Use biber instead of bibtex

# Output directory
$out_dir = 'build';

# Continuous preview mode
$preview_continuous_mode = 1;
$pdf_previewer = 'start zathura %O %S';  # Use zathura for preview

# File extensions to clean
$clean_ext = 'aux bbl bcf blg fdb_latexmk fls idx ilg ind lof log lot out run.xml synctex.gz toc nav snm vrb figlist makefile';

# Force cleaning of additional files
$clean_full_ext = 'aux bbl bcf blg fdb_latexmk fls idx ilg ind lof log lot out run.xml synctex.gz toc nav snm vrb figlist makefile acn acr alg glg glo gls ist';

# Automatically run biber when .bib files change
add_cus_dep('bib', 'bbl', 0, 'run_biber');

sub run_biber {
    my $base = shift @_;
    system("biber --bblencoding=utf8 -u -U --output_safechars \"$base\"");
    return 0;
}

# Watch for changes in additional file types
$dependents_list = 1;
$dependents_phony = 1;

# Enable shell escape for certain packages (be careful with security)
# $lualatex = 'lualatex %O -synctex=1 -interaction=nonstopmode -file-line-error -shell-escape %S';

# Maximum number of compilation runs
$max_repeat = 5;

# Show timing information
$show_time = 1;

# Recorder mode for dependency tracking
$recorder = 1;

# Error handling
$failure_cmd = 'echo "LaTeX compilation failed. Check the log file for errors."';

# Silent operation (comment out for verbose output)
# $silent = 1;

# Custom file extensions to watch
push @file_not_found, '^Package .* No file `([^\']*)\'';
push @file_not_found, '^Package .* File `([^\']*)\'.*not found';

# Watch for changes in figure directories
$ENV{'max_print_line'} = 1000;

# Improved error formatting
$latex_silent_switch = '-interaction=nonstopmode';
$pdflatex_silent_switch = '-interaction=nonstopmode';
$lualatex_silent_switch = '-interaction=nonstopmode';