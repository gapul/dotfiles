import Link from 'next/link'
import { getServerSession } from 'next-auth'
import { ArrowRightIcon, CheckIcon } from 'lucide-react'

import { authOptions } from '@/lib/auth'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

const features = [
  {
    title: 'Next.js 14',
    description: 'Built with the latest Next.js App Router for optimal performance',
  },
  {
    title: 'TypeScript',
    description: 'Fully typed codebase for better developer experience and fewer bugs',
  },
  {
    title: 'tRPC',
    description: 'End-to-end typesafe APIs with excellent developer experience',
  },
  {
    title: 'Prisma',
    description: 'Type-safe database client with automatic migrations',
  },
  {
    title: 'NextAuth.js',
    description: 'Complete authentication solution with multiple providers',
  },
  {
    title: 'Tailwind CSS',
    description: 'Utility-first CSS framework for rapid UI development',
  },
  {
    title: 'Shadcn/ui',
    description: 'Beautiful and accessible React components built on Radix UI',
  },
  {
    title: 'Stripe Integration',
    description: 'Ready-to-use payment processing with Stripe',
  },
]

export default async function HomePage() {
  const session = await getServerSession(authOptions)

  return (
    <div className="flex flex-col">
      {/* Header */}
      <header className="sticky top-0 z-50 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="container flex h-14 max-w-screen-2xl items-center">
          <div className="mr-4 flex">
            <Link href="/" className="mr-6 flex items-center space-x-2">
              <div className="h-6 w-6 rounded-md bg-primary" />
              <span className="font-bold">{{PROJECT_NAME}}</span>
            </Link>
          </div>
          <div className="flex flex-1 items-center justify-between space-x-2 md:justify-end">
            <nav className="flex items-center space-x-6">
              {session ? (
                <>
                  <Link
                    href="/dashboard"
                    className="text-sm font-medium transition-colors hover:text-primary"
                  >
                    Dashboard
                  </Link>
                  <Button asChild>
                    <Link href="/api/auth/signout">Sign Out</Link>
                  </Button>
                </>
              ) : (
                <>
                  <Link
                    href="/sign-in"
                    className="text-sm font-medium transition-colors hover:text-primary"
                  >
                    Sign In
                  </Link>
                  <Button asChild>
                    <Link href="/sign-up">Sign Up</Link>
                  </Button>
                </>
              )}
            </nav>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative">
        <div className="container relative z-10 pb-16 pt-20 text-center lg:pt-32">
          <div className="mx-auto max-w-3xl">
            <h1 className="text-4xl font-bold leading-tight tracking-tighter md:text-6xl lg:leading-[1.1]">
              Full-stack Next.js{' '}
              <span className="bg-gradient-to-r from-primary to-blue-600 bg-clip-text text-transparent">
                Application
              </span>
            </h1>
            <p className="mt-6 text-lg text-muted-foreground sm:text-xl">
              Built with Next.js 14, TypeScript, Prisma, tRPC, and Tailwind CSS.
              Everything you need to build modern web applications.
            </p>
            <div className="mt-8 flex flex-col gap-4 sm:flex-row sm:justify-center">
              {session ? (
                <Button size="lg" asChild>
                  <Link href="/dashboard">
                    Go to Dashboard
                    <ArrowRightIcon className="ml-2 h-4 w-4" />
                  </Link>
                </Button>
              ) : (
                <>
                  <Button size="lg" asChild>
                    <Link href="/sign-up">
                      Get Started
                      <ArrowRightIcon className="ml-2 h-4 w-4" />
                    </Link>
                  </Button>
                  <Button size="lg" variant="outline" asChild>
                    <Link href="/sign-in">Sign In</Link>
                  </Button>
                </>
              )}
            </div>
          </div>
        </div>
        
        {/* Background gradient */}
        <div className="absolute inset-0 -z-10 bg-gradient-to-br from-primary/10 via-transparent to-secondary/10" />
      </section>

      {/* Features Section */}
      <section className="container py-20">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold leading-tight tracking-tighter md:text-4xl">
            Everything you need to build modern web apps
          </h2>
          <p className="mt-4 text-lg text-muted-foreground">
            A comprehensive full-stack template with all the tools and libraries you need.
          </p>
        </div>
        
        <div className="mt-16 grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {features.map((feature) => (
            <Card key={feature.title} className="relative overflow-hidden">
              <CardHeader>
                <div className="flex items-center space-x-2">
                  <CheckIcon className="h-5 w-5 text-primary" />
                  <CardTitle className="text-lg">{feature.title}</CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                <CardDescription>{feature.description}</CardDescription>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* CTA Section */}
      {!session && (
        <section className="border-t bg-muted/50">
          <div className="container py-20 text-center">
            <div className="mx-auto max-w-2xl">
              <h2 className="text-3xl font-bold leading-tight tracking-tighter md:text-4xl">
                Ready to get started?
              </h2>
              <p className="mt-4 text-lg text-muted-foreground">
                Sign up now and start building your next project with our comprehensive template.
              </p>
              <div className="mt-8">
                <Button size="lg" asChild>
                  <Link href="/sign-up">
                    Create Your Account
                    <ArrowRightIcon className="ml-2 h-4 w-4" />
                  </Link>
                </Button>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* Footer */}
      <footer className="border-t">
        <div className="container py-8 text-center text-sm text-muted-foreground">
          <p>
            Built with{' '}
            <Link
              href="https://nextjs.org"
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium underline underline-offset-4"
            >
              Next.js
            </Link>
            {' '}and{' '}
            <Link
              href="https://tailwindcss.com"
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium underline underline-offset-4"
            >
              Tailwind CSS
            </Link>
            . Hosted on{' '}
            <Link
              href="https://vercel.com"
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium underline underline-offset-4"
            >
              Vercel
            </Link>
            .
          </p>
        </div>
      </footer>
    </div>
  )
}