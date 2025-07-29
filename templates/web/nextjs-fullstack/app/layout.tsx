import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import { getServerSession } from 'next-auth'

import { cn } from '@/lib/utils'
import { authOptions } from '@/lib/auth'
import { Providers } from '@/components/providers'
import { Toaster } from '@/components/ui/toaster'

import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: {
    default: '{{PROJECT_NAME}}',
    template: '%s | {{PROJECT_NAME}}',
  },
  description: 'Full-stack Next.js application with TypeScript and modern tooling',
  keywords: [
    'Next.js',
    'React',
    'TypeScript',
    'Tailwind CSS',
    'Prisma',
    'tRPC',
    'NextAuth.js',
  ],
  authors: [
    {
      name: 'Developer',
      url: 'https://github.com/developer',
    },
  ],
  creator: 'Developer',
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: process.env.NEXTAUTH_URL,
    title: '{{PROJECT_NAME}}',
    description: 'Full-stack Next.js application with TypeScript and modern tooling',
    siteName: '{{PROJECT_NAME}}',
  },
  twitter: {
    card: 'summary_large_image',
    title: '{{PROJECT_NAME}}',
    description: 'Full-stack Next.js application with TypeScript and modern tooling',
    creator: '@developer',
  },
  icons: {
    icon: '/favicon.ico',
    shortcut: '/favicon-16x16.png',
    apple: '/apple-touch-icon.png',
  },
  manifest: '/site.webmanifest',
  metadataBase: new URL(process.env.NEXTAUTH_URL || 'http://localhost:3000'),
}

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const session = await getServerSession(authOptions)

  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn(inter.className, 'min-h-screen bg-background antialiased')}>
        <Providers session={session}>
          <div className="relative flex min-h-screen flex-col">
            <div className="flex-1">{children}</div>
          </div>
          <Toaster />
        </Providers>
      </body>
    </html>
  )
}