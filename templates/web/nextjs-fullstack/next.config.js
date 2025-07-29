/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    // App Router (stable in Next.js 14)
    appDir: true,
    // Server Components (stable in Next.js 14)
    serverComponentsExternalPackages: ['prisma'],
    // Turbopack for faster development (experimental)
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
    domains: [
      'localhost',
      'utfs.io', // UploadThing
      'lh3.googleusercontent.com', // Google OAuth
      'avatars.githubusercontent.com', // GitHub OAuth
    ],
    formats: ['image/webp', 'image/avif'],
  },

  // TypeScript configuration
  typescript: {
    // Dangerously allow production builds to successfully complete even if your project has type errors
    ignoreBuildErrors: false,
  },

  // ESLint configuration
  eslint: {
    // Warning: This allows production builds to successfully complete even if your project has ESLint errors
    ignoreDuringBuilds: false,
  },

  // Compiler options
  compiler: {
    // Remove console logs in production
    removeConsole: process.env.NODE_ENV === 'production',
  },

  // Bundle analyzer
  ...(process.env.ANALYZE === 'true' && {
    webpack: (config, { isServer }) => {
      if (!isServer) {
        const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer')
        config.plugins.push(
          new BundleAnalyzerPlugin({
            analyzerMode: 'static',
            openAnalyzer: false,
            reportFilename: '../bundle-analyzer-report.html',
          })
        )
      }
      return config
    },
  }),

  // Headers for security
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          // Security headers
          {
            key: 'X-DNS-Prefetch-Control',
            value: 'on',
          },
          {
            key: 'X-XSS-Protection',
            value: '1; mode=block',
          },
          {
            key: 'X-Frame-Options',
            value: 'SAMEORIGIN',
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'Referrer-Policy',
            value: 'origin-when-cross-origin',
          },
          // HSTS header for HTTPS
          ...(process.env.NODE_ENV === 'production'
            ? [
                {
                  key: 'Strict-Transport-Security',
                  value: 'max-age=31536000; includeSubDomains; preload',
                },
              ]
            : []),
        ],
      },
    ]
  },

  // Redirects
  async redirects() {
    return [
      // Redirect /login to /sign-in
      {
        source: '/login',
        destination: '/sign-in',
        permanent: true,
      },
      // Redirect /register to /sign-up
      {
        source: '/register',
        destination: '/sign-up',
        permanent: true,
      },
    ]
  },

  // Environment variables
  env: {
    CUSTOM_KEY: process.env.CUSTOM_KEY,
  },

  // Performance optimizations
  swcMinify: true,
  output: 'standalone',

  // Webpack configuration
  webpack: (config, { dev, isServer }) => {
    // Fix for canvas and other packages
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
      }
    }

    // Optimize for production
    if (!dev) {
      config.resolve.alias = {
        ...config.resolve.alias,
        // Reduce bundle size by using production builds
        '@prisma/client': '@prisma/client',
      }
    }

    return config
  },

  // Experimental features for better performance
  experimental: {
    // Use SWC for faster compilation
    swcTraceProfiling: true,
    // Server actions (stable in Next.js 14)
    serverActions: true,
    // Parallel routes and intercepting routes
    parallelRoutes: true,
    // Instrumentation for monitoring
    instrumentationHook: true,
  },
}

module.exports = nextConfig