# Web開発環境のCI/CD最適化とテスト自動化 - TODO

**ID**: todo-7  
**優先度**: 中  
**推定時間**: 4-5時間  
**ステータス**: 基盤完了・最適化待ち

## 概要

現在のWeb開発環境は基本的な設定が完了しているが、CI/CD最適化、自動テスト、パフォーマンス監視などの高度な機能が未実装。

## 現在の状況

### 完了済み機能
- ✅ React/Next.js開発環境
- ✅ TypeScript/JavaScript開発支援
- ✅ Vite/Webpack ビルドツール
- ✅ ESLint/Prettier コード品質管理
- ✅ Docker/Docker Compose統合

### 未実装・最適化が必要な機能
- ❌ CI/CDパイプライン最適化
- ❌ 自動テストスイート統合
- ❌ パフォーマンス監視
- ❌ デプロイメント自動化
- ❌ 開発環境の高速化

## 実装目標

- **CI/CD最適化**: ビルド時間短縮とパイプライン効率化
- **テスト自動化**: 単体・統合・E2Eテストの完全自動化
- **パフォーマンス監視**: Core Web Vitals監視とバンドル分析
- **デプロイメント**: ゼロダウンタイムデプロイとロールバック機能
- **開発DX向上**: ホットリロード、キャッシュ最適化、開発速度向上

## 実装手順

### Phase 1: CI/CD パイプライン最適化

#### 1. GitHub Actions ワークフロー強化
```yaml
# .github/workflows/web-ci-cd.yml
name: Web Development CI/CD

on:
  push:
    branches: [main, develop]
    paths: ['web/**', 'nix/common/development/web/**']
  pull_request:
    branches: [main]
    paths: ['web/**', 'nix/common/development/web/**']

env:
  NODE_VERSION: '20'
  PNPM_VERSION: '8'

jobs:
  # 依存関係キャッシュ最適化
  cache-dependencies:
    runs-on: ubuntu-latest
    outputs:
      cache-hit: ${{ steps.cache.outputs.cache-hit }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Cache Node.js dependencies
        id: cache
        uses: actions/cache@v3
        with:
          path: |
            ~/.pnpm-store
            node_modules
            .next/cache
          key: ${{ runner.os }}-node-${{ hashFiles('**/pnpm-lock.yaml') }}
          restore-keys: |
            ${{ runner.os }}-node-

  # 並列テスト実行
  test:
    needs: cache-dependencies
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test-type: [unit, integration, e2e]
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          
      - name: Setup pnpm
        uses: pnpm/action-setup@v2
        with:
          version: ${{ env.PNPM_VERSION }}
          
      - name: Install dependencies
        if: needs.cache-dependencies.outputs.cache-hit != 'true'
        run: pnpm install --frozen-lockfile
        
      - name: Run tests
        run: |
          case "${{ matrix.test-type }}" in
            unit)
              pnpm test:unit --coverage
              ;;
            integration)
              pnpm test:integration
              ;;
            e2e)
              pnpm test:e2e --headless
              ;;
          esac
          
      - name: Upload coverage
        if: matrix.test-type == 'unit'
        uses: codecov/codecov-action@v3

  # ビルド最適化
  build:
    needs: [cache-dependencies, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build application
        run: |
          # Next.js最適化ビルド
          NEXT_TELEMETRY_DISABLED=1 pnpm build
          
          # バンドルサイズ分析
          pnpm analyze
          
      - name: Upload build artifacts
        uses: actions/upload-artifact@v3
        with:
          name: build-assets
          path: |
            .next/
            dist/
            build/

  # セキュリティスキャン
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run security audit
        run: |
          pnpm audit --prod
          
      - name: SAST scan
        uses: github/super-linter@v4
        env:
          DEFAULT_BRANCH: main
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### 2. ビルド時間最適化設定
```nix
# nix/common/development/web/ci-optimization.nix
{ config, lib, pkgs, ... }:

{
  # CI/CD最適化パッケージ
  home.packages = with pkgs; [
    # ビルドツール最適化
    esbuild          # 高速JavaScriptバンドラー
    swc              # 高速TypeScriptコンパイラー
    turbo            # モノレポビルドシステム
    
    # テストツール
    playwright       # E2Eテストブラウザー
    lighthouse       # パフォーマンス測定
    
    # CI/CD支援ツール
    act              # GitHub Actions ローカル実行
    lefthook         # Git hooks管理
  ];

  # 開発環境設定ファイル
  home.file.".turbo.json" = {
    text = builtins.toJSON {
      "$schema" = "https://turbo.build/schema.json";
      pipeline = {
        build = {
          dependsOn = ["^build"];
          outputs = [".next/**" "dist/**"];
          env = ["NODE_ENV"];
        };
        test = {
          dependsOn = ["^build"];
          outputs = ["coverage/**"];
        };
        lint = {
          outputs = [];
        };
        dev = {
          cache = false;
          persistent = true;
        };
      };
    };
  };

  # Playwright設定
  home.file."playwright.config.ts" = {
    text = ''
      import { defineConfig, devices } from '@playwright/test';

      export default defineConfig({
        testDir: './e2e',
        fullyParallel: true,
        forbidOnly: !!process.env.CI,
        retries: process.env.CI ? 2 : 0,
        workers: process.env.CI ? 1 : undefined,
        reporter: 'html',
        
        use: {
          baseURL: 'http://localhost:3000',
          trace: 'on-first-retry',
        },

        projects: [
          {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] },
          },
          {
            name: 'firefox',
            use: { ...devices['Desktop Firefox'] },
          },
          {
            name: 'webkit',
            use: { ...devices['Desktop Safari'] },
          },
        ],

        webServer: {
          command: 'pnpm dev',
          url: 'http://localhost:3000',
          reuseExistingServer: !process.env.CI,
        },
      });
    '';
  };
}
```

### Phase 2: テスト自動化強化

#### 1. 包括的テストスイート設定
```json
// package.json テストスクリプト強化
{
  "scripts": {
    "test": "turbo run test",
    "test:unit": "vitest run --coverage",
    "test:unit:watch": "vitest",
    "test:integration": "vitest run --config vitest.integration.config.ts",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:visual": "chromatic --exit-zero-on-changes",
    "test:performance": "lighthouse-ci autorun",
    "test:a11y": "axe-core test",
    "test:all": "pnpm test:unit && pnpm test:integration && pnpm test:e2e"
  }
}
```

#### 2. テスト設定ファイル
```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'src/test/',
        '**/*.d.ts',
        '**/*.config.*',
      ],
      thresholds: {
        global: {
          branches: 80,
          functions: 80,
          lines: 80,
          statements: 80,
        },
      },
    },
  },
});
```

### Phase 3: パフォーマンス監視

#### 1. Core Web Vitals 監視
```javascript
// src/lib/performance.ts
export const reportWebVitals = (metric: any) => {
  // 開発環境での監視
  if (process.env.NODE_ENV === 'development') {
    console.log(metric);
  }
  
  // プロダクション環境での計測
  if (process.env.NODE_ENV === 'production') {
    // Analytics service integration
    gtag('event', metric.name, {
      custom_map: { metric_id: 'custom_metric' },
      value: Math.round(metric.value),
      event_category: 'Web Vitals',
      non_interaction: true,
    });
  }
};

// Bundle analyzer integration
export const analyzeBundleSize = () => {
  if (typeof window !== 'undefined' && 'performance' in window) {
    const observer = new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => {
        if (entry.entryType === 'navigation') {
          console.log('Page Load Time:', entry.loadEventEnd);
        }
      });
    });
    observer.observe({ entryTypes: ['navigation'] });
  }
};
```

#### 2. バンドル分析自動化
```javascript
// next.config.js 拡張
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});

module.exports = withBundleAnalyzer({
  // 最適化設定
  experimental: {
    optimizeCss: true,
    optimizeImages: true,
    modern: true,
  },
  
  // バンドル最適化
  webpack: (config, { dev, isServer }) => {
    if (!dev && !isServer) {
      config.optimization.splitChunks = {
        cacheGroups: {
          default: false,
          vendors: false,
          vendor: {
            chunks: 'all',
            name: 'vendor',
            test: /node_modules/,
          },
        },
      };
    }
    return config;
  },
});
```

### Phase 4: デプロイメント自動化

#### 1. ゼロダウンタイムデプロイ
```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]
    paths: ['web/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build and Deploy
        run: |
          # Blue-Green デプロイメント
          docker build -t app:${{ github.sha }} .
          
          # ヘルスチェック付きデプロイ
          docker-compose -f docker-compose.prod.yml up -d --scale app=2
          
          # カナリアデプロイ（段階的トラフィック移行）
          ./scripts/canary-deploy.sh ${{ github.sha }}
          
      - name: Smoke tests
        run: |
          # デプロイ後の動作確認
          curl -f https://your-app.com/health || exit 1
          pnpm test:smoke
          
      - name: Rollback on failure
        if: failure()
        run: |
          docker-compose -f docker-compose.prod.yml down
          ./scripts/rollback.sh
```

#### 2. 環境別デプロイ設定
```nix
# nix/common/development/web/deployment.nix
{ config, lib, pkgs, ... }:

{
  # デプロイメントツール
  home.packages = with pkgs; [
    docker-compose
    kubectl
    terraform
    ansible
  ];

  # 環境設定ファイル
  home.file.".env.example" = {
    text = ''
      # Development
      NODE_ENV=development
      PORT=3000
      DATABASE_URL=postgresql://localhost/myapp_dev
      
      # Production
      # NODE_ENV=production
      # PORT=8080
      # DATABASE_URL=postgresql://prod-server/myapp_prod
      
      # Analytics
      GOOGLE_ANALYTICS_ID=
      SENTRY_DSN=
      
      # Feature flags
      FEATURE_NEW_UI=false
      FEATURE_ANALYTICS=true
    '';
  };

  # Docker設定
  home.file."Dockerfile" = {
    text = ''
      FROM node:20-alpine AS deps
      RUN apk add --no-cache libc6-compat
      WORKDIR /app
      COPY package.json pnpm-lock.yaml ./
      RUN corepack enable pnpm && pnpm install --frozen-lockfile

      FROM node:20-alpine AS builder
      WORKDIR /app
      COPY --from=deps /app/node_modules ./node_modules
      COPY . .
      RUN corepack enable pnpm && pnpm build

      FROM node:20-alpine AS runner
      WORKDIR /app
      ENV NODE_ENV production
      RUN addgroup --system --gid 1001 nodejs
      RUN adduser --system --uid 1001 nextjs
      
      COPY --from=builder /app/public ./public
      COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
      COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
      
      USER nextjs
      EXPOSE 3000
      ENV PORT 3000
      
      CMD ["node", "server.js"]
    '';
  };
}
```

### Phase 5: 開発体験 (DX) 向上

#### 1. 高速開発環境
```nix
# nix/common/development/web/dx-optimization.nix
{ config, lib, pkgs, ... }:

{
  # 開発効率化ツール
  home.packages = with pkgs; [
    # ホットリロード最適化
    nodemon
    concurrently
    
    # デバッグツール
    reactotron
    flipper
    
    # 開発サーバー最適化
    vite
    turbo
  ];

  # 開発用設定
  home.file."turbo.json" = {
    text = builtins.toJSON {
      pipeline = {
        dev = {
          cache = false;
          persistent = true;
          env = ["NODE_ENV=development"];
        };
        build = {
          dependsOn = ["^build"];
          outputs = [".next/**"];
          env = ["NODE_ENV"];
        };
      };
    };
  };

  # 開発用スクリプト
  home.file."bin/dev-optimize" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      
      echo "🚀 Optimizing development environment..."
      
      # Node.js最適化
      export NODE_OPTIONS="--max-old-space-size=8192"
      export NEXT_TELEMETRY_DISABLED=1
      
      # キャッシュクリア
      pnpm store prune
      rm -rf .next/cache
      
      # 依存関係最適化
      pnpm install --prefer-offline
      
      echo "✅ Development environment optimized!"
    '';
  };
}
```

## 完了条件

### CI/CD最適化
- [ ] ビルド時間が50%以上短縮されている
- [ ] 並列テスト実行が正常に動作する
- [ ] キャッシュ最適化が効果的に働いている
- [ ] セキュリティスキャンが自動実行される

### テスト自動化
- [ ] 単体テストカバレッジが80%以上
- [ ] 統合テストが正常に動作する
- [ ] E2Eテストが安定して実行される
- [ ] パフォーマンステストが自動実行される

### パフォーマンス監視
- [ ] Core Web Vitalsが監視されている
- [ ] バンドルサイズ分析が自動化されている
- [ ] パフォーマンス回帰が検出される
- [ ] 最適化提案が自動生成される

### デプロイメント
- [ ] ゼロダウンタイムデプロイが実現されている
- [ ] 自動ロールバック機能が動作する
- [ ] 環境別デプロイが正常に動作する
- [ ] デプロイ後のヘルスチェックが機能する

## 関連ファイル

- `.github/workflows/web-ci-cd.yml` - CI/CDワークフロー
- `nix/common/development/web/ci-optimization.nix` - CI最適化設定
- `nix/common/development/web/deployment.nix` - デプロイ設定
- `playwright.config.ts` - E2Eテスト設定
- `vitest.config.ts` - 単体テスト設定
- `next.config.js` - バンドル最適化設定

## 技術スタック

### テストツール
- **Vitest**: 高速単体テスト
- **Playwright**: クロスブラウザE2Eテスト
- **Testing Library**: React コンポーネントテスト
- **Chromatic**: ビジュアルリグレッションテスト

### パフォーマンス
- **Lighthouse CI**: Core Web Vitals 監視
- **Bundle Analyzer**: バンドルサイズ分析
- **Turbo**: モノレポビルド最適化
- **SWC**: 高速TypeScriptコンパイル

### デプロイメント
- **Docker**: コンテナ化
- **GitHub Actions**: CI/CDパイプライン
- **Terraform**: インフラストラクチャ管理
- **Blue-Green**: ゼロダウンタイムデプロイ

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant