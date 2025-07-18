# Web Development Performance Monitoring
# Comprehensive performance monitoring and optimization tools

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.web.performance-monitoring;
in
{
  options.dotfiles.development.web.performance-monitoring = {
    enable = mkEnableOption "Web development performance monitoring";
    
    profile = mkOption {
      type = types.enum [ "basic" "standard" "advanced" "enterprise" ];
      default = "standard";
      description = "Performance monitoring profile";
    };
    
    features = {
      coreWebVitals = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Core Web Vitals monitoring";
      };
      
      bundleAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Enable bundle size analysis";
      };
      
      runtimePerformance = mkOption {
        type = types.bool;
        default = true;
        description = "Enable runtime performance monitoring";
      };
      
      networkOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable network performance optimization";
      };
      
      accessibilityMonitoring = mkOption {
        type = types.bool;
        default = true;
        description = "Enable accessibility monitoring";
      };
    };
    
    thresholds = {
      performance = mkOption {
        type = types.int;
        default = 80;
        description = "Performance score threshold (0-100)";
      };
      
      accessibility = mkOption {
        type = types.int;
        default = 90;
        description = "Accessibility score threshold (0-100)";
      };
      
      bestPractices = mkOption {
        type = types.int;
        default = 80;
        description = "Best practices score threshold (0-100)";
      };
      
      seo = mkOption {
        type = types.int;
        default = 80;
        description = "SEO score threshold (0-100)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Performance monitoring tools
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core monitoring tools
      lighthouse
      nodePackages."@lhci/cli"
      
      # Bundle analysis
      nodePackages.webpack-bundle-analyzer
      
      # Performance profiling
      chromium  # For headless performance testing
    ] ++ optionals (cfg.profile == "advanced" || cfg.profile == "enterprise") [
      # Advanced monitoring tools
      prometheus
      grafana
    ];

    # Lighthouse CI configuration
    home-manager.users.yuki.home.file."lighthouserc.js" = mkIf cfg.features.coreWebVitals {
      text = ''
        module.exports = {
          ci: {
            collect: {
              url: [
                'http://localhost:3000',
                'http://localhost:3000/about',
                'http://localhost:3000/contact',
              ],
              startServerCommand: 'pnpm start',
              startServerReadyPattern: 'ready',
              startServerReadyTimeout: 30000,
              numberOfRuns: 3,
              settings: {
                chromeFlags: '--no-sandbox --headless',
                preset: 'desktop',
                onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
              },
            },
            assert: {
              assertions: {
                'categories:performance': ['warn', { minScore: ${toString cfg.thresholds.performance} / 100 }],
                'categories:accessibility': ['error', { minScore: ${toString cfg.thresholds.accessibility} / 100 }],
                'categories:best-practices': ['warn', { minScore: ${toString cfg.thresholds.bestPractices} / 100 }],
                'categories:seo': ['warn', { minScore: ${toString cfg.thresholds.seo} / 100 }],
                
                // Core Web Vitals
                'first-contentful-paint': ['warn', { maxNumericValue: 2000 }],
                'largest-contentful-paint': ['error', { maxNumericValue: 4000 }],
                'cumulative-layout-shift': ['error', { maxNumericValue: 0.1 }],
                'total-blocking-time': ['warn', { maxNumericValue: 300 }],
                
                // Performance budgets
                'resource-summary:document:size': ['error', { maxNumericValue: 100000 }],
                'resource-summary:script:size': ['error', { maxNumericValue: 500000 }],
                'resource-summary:stylesheet:size': ['error', { maxNumericValue: 50000 }],
                'resource-summary:image:size': ['warn', { maxNumericValue: 1000000 }],
              },
            },
            upload: {
              target: 'temporary-public-storage',
            },
            server: {
              port: 9001,
              storage: {
                storageMethod: 'filesystem',
                storagePath: './lighthouse-results',
              },
            },
          },
        };
      '';
    };

    # Web Vitals monitoring script
    home-manager.users.yuki.home.file."src/lib/web-vitals.ts" = mkIf cfg.features.coreWebVitals {
      text = ''
        import { getCLS, getFID, getFCP, getLCP, getTTFB, Metric } from 'web-vitals';

        // Web Vitals thresholds
        const THRESHOLDS = {
          CLS: { good: 0.1, poor: 0.25 },
          FID: { good: 100, poor: 300 },
          FCP: { good: 1800, poor: 3000 },
          LCP: { good: 2500, poor: 4000 },
          TTFB: { good: 800, poor: 1800 },
        };

        type MetricName = 'CLS' | 'FID' | 'FCP' | 'LCP' | 'TTFB';

        interface WebVitalMetric extends Metric {
          rating: 'good' | 'needs-improvement' | 'poor';
        }

        function getMetricRating(name: MetricName, value: number): 'good' | 'needs-improvement' | 'poor' {
          const threshold = THRESHOLDS[name];
          if (value <= threshold.good) return 'good';
          if (value <= threshold.poor) return 'needs-improvement';
          return 'poor';
        }

        function sendToAnalytics(metric: WebVitalMetric) {
          // Development logging
          if (process.env.NODE_ENV === 'development') {
            console.group(`🔍 Web Vital: ''${metric.name}`);
            console.log(`Value: ''${metric.value}`);
            console.log(`Rating: ''${metric.rating}`);
            console.log(`Delta: ''${metric.delta}`);
            console.log(`ID: ''${metric.id}`);
            console.groupEnd();
          }

          // Production analytics
          if (process.env.NODE_ENV === 'production') {
            // Google Analytics 4
            if (typeof gtag !== 'undefined') {
              gtag('event', metric.name, {
                custom_map: { metric_id: 'custom_metric' },
                value: Math.round(metric.value),
                metric_rating: metric.rating,
                event_category: 'Web Vitals',
                non_interaction: true,
              });
            }

            // Custom analytics endpoint
            if (typeof fetch !== 'undefined') {
              fetch('/api/analytics/web-vitals', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  name: metric.name,
                  value: metric.value,
                  rating: metric.rating,
                  delta: metric.delta,
                  id: metric.id,
                  url: window.location.href,
                  timestamp: Date.now(),
                }),
              }).catch(console.error);
            }
          }
        }

        function createMetricHandler(name: MetricName) {
          return (metric: Metric) => {
            const rating = getMetricRating(name, metric.value);
            const webVitalMetric: WebVitalMetric = { ...metric, rating };
            sendToAnalytics(webVitalMetric);
          };
        }

        // Initialize Web Vitals monitoring
        export function initWebVitals() {
          getCLS(createMetricHandler('CLS'));
          getFID(createMetricHandler('FID'));
          getFCP(createMetricHandler('FCP'));
          getLCP(createMetricHandler('LCP'));
          getTTFB(createMetricHandler('TTFB'));
        }

        // Performance observer for custom metrics
        export function observePerformance() {
          if (typeof window === 'undefined' || !('PerformanceObserver' in window)) {
            return;
          }

          // Long tasks observer
          const longTaskObserver = new PerformanceObserver((list) => {
            list.getEntries().forEach((entry) => {
              if (entry.duration > 50) {
                console.warn(`🐌 Long task detected: ''${entry.duration}ms`, entry);
                
                // Send to analytics
                if (process.env.NODE_ENV === 'production') {
                  sendToAnalytics({
                    name: 'long-task',
                    value: entry.duration,
                    rating: entry.duration > 100 ? 'poor' : 'needs-improvement',
                    delta: entry.duration,
                    id: entry.name + '-' + Date.now(),
                  } as WebVitalMetric);
                }
              }
            });
          });

          try {
            longTaskObserver.observe({ entryTypes: ['longtask'] });
          } catch (e) {
            console.warn('Long task observer not supported');
          }

          // Navigation timing observer
          const navigationObserver = new PerformanceObserver((list) => {
            list.getEntries().forEach((entry) => {
              const navigationEntry = entry as PerformanceNavigationTiming;
              
              const metrics = {
                'dns-lookup': navigationEntry.domainLookupEnd - navigationEntry.domainLookupStart,
                'tcp-connection': navigationEntry.connectEnd - navigationEntry.connectStart,
                'request-response': navigationEntry.responseEnd - navigationEntry.requestStart,
                'dom-processing': navigationEntry.domContentLoadedEventEnd - navigationEntry.responseEnd,
                'load-complete': navigationEntry.loadEventEnd - navigationEntry.domContentLoadedEventEnd,
              };

              Object.entries(metrics).forEach(([name, value]) => {
                if (value > 0) {
                  console.log(`📊 ''${name}: ''${value}ms`);
                }
              });
            });
          });

          try {
            navigationObserver.observe({ entryTypes: ['navigation'] });
          } catch (e) {
            console.warn('Navigation observer not supported');
          }
        }

        // Bundle size analyzer
        export function analyzeBundleSize() {
          if (typeof window === 'undefined') return;

          const scripts = Array.from(document.querySelectorAll('script[src]'));
          const stylesheets = Array.from(document.querySelectorAll('link[rel="stylesheet"]'));

          const resources = {
            scripts: scripts.map(script => ({
              src: (script as HTMLScriptElement).src,
              size: 0, // Would need to be measured via Resource Timing API
            })),
            stylesheets: stylesheets.map(link => ({
              href: (link as HTMLLinkElement).href,
              size: 0,
            })),
          };

          // Use Resource Timing API to get actual sizes
          const resourceEntries = performance.getEntriesByType('resource') as PerformanceResourceTiming[];
          
          resourceEntries.forEach(entry => {
            const size = entry.transferSize || entry.encodedBodySize || 0;
            
            if (entry.name.includes('.js')) {
              const script = resources.scripts.find(s => entry.name.includes(s.src));
              if (script) script.size = size;
            } else if (entry.name.includes('.css')) {
              const stylesheet = resources.stylesheets.find(s => entry.name.includes(s.href));
              if (stylesheet) stylesheet.size = size;
            }
          });

          const totalScriptSize = resources.scripts.reduce((sum, script) => sum + script.size, 0);
          const totalStylesheetSize = resources.stylesheets.reduce((sum, stylesheet) => sum + stylesheet.size, 0);

          console.group('📦 Bundle Analysis');
          console.log(`Scripts: ''${(totalScriptSize / 1024).toFixed(2)} KB`);
          console.log(`Stylesheets: ''${(totalStylesheetSize / 1024).toFixed(2)} KB`);
          console.log(`Total: ''${((totalScriptSize + totalStylesheetSize) / 1024).toFixed(2)} KB`);
          console.groupEnd();

          return {
            scripts: resources.scripts,
            stylesheets: resources.stylesheets,
            totalSize: totalScriptSize + totalStylesheetSize,
          };
        }
      '';
    };

    # Next.js performance configuration
    home-manager.users.yuki.home.file."next.config.js" = mkIf cfg.features.bundleAnalysis {
      text = ''
        const withBundleAnalyzer = require('@next/bundle-analyzer')({
          enabled: process.env.ANALYZE === 'true',
        });

        /** @type {import('next').NextConfig} */
        const nextConfig = {
          // Performance optimizations
          experimental: {
            optimizeCss: true,
            optimizePackageImports: ['lucide-react', '@radix-ui/react-icons'],
            turbo: {
              rules: {
                '*.svg': {
                  loaders: ['@svgr/webpack'],
                  as: '*.js',
                },
              },
            },
          },

          // Image optimization
          images: {
            formats: ['image/avif', 'image/webp'],
            minimumCacheTTL: 60 * 60 * 24 * 30, // 30 days
            dangerouslyAllowSVG: false,
          },

          // Compression
          compress: true,

          // PWA support
          pwa: {
            dest: 'public',
            register: true,
            skipWaiting: true,
            disable: process.env.NODE_ENV === 'development',
          },

          // Bundle optimization
          webpack: (config, { dev, isServer, webpack }) => {
            // Bundle analyzer
            if (process.env.ANALYZE === 'true') {
              config.plugins.push(
                new webpack.DefinePlugin({
                  'process.env.BUNDLE_ANALYZE': JSON.stringify('true'),
                })
              );
            }

            // Production optimizations
            if (!dev && !isServer) {
              // Split chunks optimization
              config.optimization.splitChunks = {
                chunks: 'all',
                cacheGroups: {
                  default: false,
                  vendors: false,
                  // Vendor chunk
                  vendor: {
                    name: 'vendor',
                    chunks: 'all',
                    test: /[\\/]node_modules[\\/]/,
                    priority: 20,
                  },
                  // React chunk
                  react: {
                    name: 'react',
                    chunks: 'all',
                    test: /[\\/]node_modules[\\/](react|react-dom)[\\/]/,
                    priority: 30,
                  },
                  // Common chunk
                  common: {
                    name: 'common',
                    chunks: 'all',
                    minChunks: 2,
                    priority: 10,
                    reuseExistingChunk: true,
                    enforce: true,
                  },
                },
              };

              // Tree shaking
              config.optimization.usedExports = true;
              config.optimization.sideEffects = false;
            }

            return config;
          },

          // Headers for performance
          async headers() {
            return [
              {
                source: '/(.*)',
                headers: [
                  {
                    key: 'X-Content-Type-Options',
                    value: 'nosniff',
                  },
                  {
                    key: 'X-Frame-Options',
                    value: 'DENY',
                  },
                  {
                    key: 'X-XSS-Protection',
                    value: '1; mode=block',
                  },
                  {
                    key: 'Referrer-Policy',
                    value: 'strict-origin-when-cross-origin',
                  },
                ],
              },
              {
                source: '/static/(.*)',
                headers: [
                  {
                    key: 'Cache-Control',
                    value: 'public, max-age=31536000, immutable',
                  },
                ],
              },
            ];
          },
        };

        module.exports = withBundleAnalyzer(nextConfig);
      '';
    };

    # Performance monitoring scripts
    home-manager.users.yuki.home.file."bin/perf-monitor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        COMMAND="''${1:-help}"
        URL="''${2:-http://localhost:3000}"
        
        case "$COMMAND" in
          lighthouse)
            echo "🔍 Running Lighthouse audit on $URL"
            lighthouse "$URL" \
              --chrome-flags="--headless --no-sandbox" \
              --output=html \
              --output-path=./lighthouse-report.html \
              --view
            ;;
            
          vitals)
            echo "📊 Monitoring Core Web Vitals on $URL"
            lighthouse "$URL" \
              --chrome-flags="--headless --no-sandbox" \
              --only-categories=performance \
              --output=json \
              --output-path=./web-vitals.json
            
            # Extract Core Web Vitals
            if command -v jq &>/dev/null; then
              echo ""
              echo "Core Web Vitals Results:"
              jq -r '.audits["first-contentful-paint"].displayValue // "N/A"' web-vitals.json | sed 's/^/  FCP: /'
              jq -r '.audits["largest-contentful-paint"].displayValue // "N/A"' web-vitals.json | sed 's/^/  LCP: /'
              jq -r '.audits["cumulative-layout-shift"].displayValue // "N/A"' web-vitals.json | sed 's/^/  CLS: /'
              jq -r '.audits["total-blocking-time"].displayValue // "N/A"' web-vitals.json | sed 's/^/  TBT: /'
            fi
            ;;
            
          bundle)
            echo "📦 Analyzing bundle size..."
            
            if [[ -f "package.json" ]]; then
              # Build with bundle analyzer
              ANALYZE=true npm run build
              
              echo "Bundle analysis completed. Check the output above."
            else
              echo "❌ No package.json found in current directory"
              exit 1
            fi
            ;;
            
          continuous)
            echo "🔄 Starting continuous performance monitoring..."
            
            while true; do
              echo "$(date): Running performance check..."
              
              # Quick Lighthouse check
              lighthouse "$URL" \
                --chrome-flags="--headless --no-sandbox" \
                --only-categories=performance \
                --output=json \
                --output-path=./perf-check-$(date +%Y%m%d-%H%M%S).json \
                --quiet
              
              echo "Performance check completed. Waiting 5 minutes..."
              sleep 300
            done
            ;;
            
          compare)
            if [[ $# -lt 3 ]]; then
              echo "Usage: perf-monitor compare <url1> <url2>"
              exit 1
            fi
            
            local url1="$2"
            local url2="$3"
            
            echo "🔄 Comparing performance between:"
            echo "  URL 1: $url1"
            echo "  URL 2: $url2"
            
            # Run Lighthouse on both URLs
            lighthouse "$url1" \
              --chrome-flags="--headless --no-sandbox" \
              --only-categories=performance \
              --output=json \
              --output-path=./perf-url1.json \
              --quiet
              
            lighthouse "$url2" \
              --chrome-flags="--headless --no-sandbox" \
              --only-categories=performance \
              --output=json \
              --output-path=./perf-url2.json \
              --quiet
            
            if command -v jq &>/dev/null; then
              echo ""
              echo "Performance Comparison:"
              echo "========================"
              
              score1=$(jq -r '.categories.performance.score * 100' perf-url1.json)
              score2=$(jq -r '.categories.performance.score * 100' perf-url2.json)
              
              echo "Performance Score:"
              echo "  URL 1: $score1"
              echo "  URL 2: $score2"
              
              if (( $(echo "$score1 > $score2" | bc -l) )); then
                echo "  Winner: URL 1 (+$(echo "$score1 - $score2" | bc -l) points)"
              elif (( $(echo "$score2 > $score1" | bc -l) )); then
                echo "  Winner: URL 2 (+$(echo "$score2 - $score1" | bc -l) points)"
              else
                echo "  Result: Tie"
              fi
            fi
            ;;
            
          help)
            cat << EOF
        Usage: perf-monitor <command> [options]
        
        COMMANDS:
          lighthouse [url]       Run full Lighthouse audit
          vitals [url]          Monitor Core Web Vitals
          bundle                Analyze bundle size
          continuous [url]      Continuous performance monitoring
          compare <url1> <url2> Compare performance between URLs
          help                  Show this help message
          
        EXAMPLES:
          perf-monitor lighthouse                           # Audit localhost:3000
          perf-monitor lighthouse https://example.com       # Audit external site
          perf-monitor vitals                              # Check Core Web Vitals
          perf-monitor bundle                              # Analyze bundle
          perf-monitor compare http://localhost:3000 https://production.com
        EOF
            ;;
            
          *)
            echo "❌ Unknown command: $COMMAND"
            echo "Use 'perf-monitor help' for available commands"
            exit 1
            ;;
        esac
      '';
    };

    # Performance budget configuration
    home-manager.users.yuki.home.file."performance-budget.json" = {
      text = builtins.toJSON {
        budgets = [
          {
            resourceSizes = [
              {
                resourceType = "script";
                budget = 500; # KB
              }
              {
                resourceType = "stylesheet";
                budget = 50; # KB
              }
              {
                resourceType = "image";
                budget = 1000; # KB
              }
              {
                resourceType = "media";
                budget = 2000; # KB
              }
              {
                resourceType = "font";
                budget = 100; # KB
              }
              {
                resourceType = "document";
                budget = 100; # KB
              }
              {
                resourceType = "other";
                budget = 200; # KB
              }
            ];
            resourceCounts = [
              {
                resourceType = "script";
                budget = 10;
              }
              {
                resourceType = "stylesheet";
                budget = 5;
              }
              {
                resourceType = "image";
                budget = 20;
              }
              {
                resourceType = "font";
                budget = 5;
              }
            ];
          }
        ];
      };
    };

    # Shell aliases for performance monitoring
    home-manager.users.yuki.programs.zsh.shellAliases = {
      "perf-audit" = "perf-monitor lighthouse";
      "perf-vitals" = "perf-monitor vitals";
      "perf-bundle" = "perf-monitor bundle";
      "perf-compare" = "perf-monitor compare";
      "lighthouse-ci" = "lhci autorun";
    };

    # Environment variables for performance monitoring
    home-manager.users.yuki.home.sessionVariables = {
      # Lighthouse configuration
      LIGHTHOUSE_CHROME_PATH = "${pkgs.chromium}/bin/chromium";
      
      # Performance monitoring
      PERFORMANCE_MONITORING = "true";
      WEB_VITALS_REPORTING = mkDefault "true";
      
      # Bundle analysis
      BUNDLE_ANALYZE = mkDefault "false";
    };
  };
}