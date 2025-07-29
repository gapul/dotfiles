import { NextAuthOptions } from 'next-auth'
import { PrismaAdapter } from '@next-auth/prisma-adapter'
import CredentialsProvider from 'next-auth/providers/credentials'
import GoogleProvider from 'next-auth/providers/google'
import GitHubProvider from 'next-auth/providers/github'
import bcrypt from 'bcryptjs'
import { db } from '@/lib/db'
import { loginSchema } from '@/lib/validations'

export const authOptions: NextAuthOptions = {
  adapter: PrismaAdapter(db),
  session: {
    strategy: 'jwt',
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  jwt: {
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  pages: {
    signIn: '/sign-in',
    signUp: '/sign-up',
    error: '/sign-in',
  },
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
      profile(profile) {
        return {
          id: profile.sub,
          name: profile.name,
          email: profile.email,
          image: profile.picture,
          role: 'user',
        }
      },
    }),
    GitHubProvider({
      clientId: process.env.GITHUB_CLIENT_ID!,
      clientSecret: process.env.GITHUB_CLIENT_SECRET!,
      profile(profile) {
        return {
          id: profile.id.toString(),
          name: profile.name || profile.login,
          email: profile.email,
          image: profile.avatar_url,
          role: 'user',
        }
      },
    }),
    CredentialsProvider({
      name: 'credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          throw new Error('Missing credentials')
        }

        // Validate input
        const validatedFields = loginSchema.safeParse(credentials)
        if (!validatedFields.success) {
          throw new Error('Invalid credentials format')
        }

        const { email, password } = validatedFields.data

        // Find user
        const user = await db.user.findUnique({
          where: { email: email.toLowerCase() },
        })

        if (!user || !user.password) {
          throw new Error('Invalid credentials')
        }

        // Check if user is active
        if (!user.emailVerified) {
          throw new Error('Please verify your email before signing in')
        }

        // Verify password
        const isValidPassword = await bcrypt.compare(password, user.password)
        if (!isValidPassword) {
          throw new Error('Invalid credentials')
        }

        // Update last login
        await db.user.update({
          where: { id: user.id },
          data: { lastLoginAt: new Date() },
        })

        return {
          id: user.id,
          name: user.name,
          email: user.email,
          image: user.image,
          role: user.role,
        }
      },
    }),
  ],
  callbacks: {
    async signIn({ user, account, profile }) {
      // Allow OAuth sign-ins
      if (account?.provider !== 'credentials') {
        return true
      }

      // For credentials, user validation is done in authorize function
      return true
    },
    async jwt({ token, user, account }) {
      // Initial sign in
      if (user) {
        token.role = user.role
      }

      // Refresh user data from database on each request
      if (token.sub) {
        const dbUser = await db.user.findUnique({
          where: { id: token.sub },
          select: {
            id: true,
            name: true,
            email: true,
            image: true,
            role: true,
            emailVerified: true,
          },
        })

        if (dbUser) {
          token.name = dbUser.name
          token.email = dbUser.email
          token.picture = dbUser.image
          token.role = dbUser.role
          token.emailVerified = dbUser.emailVerified
        }
      }

      return token
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.sub!
        session.user.role = token.role as string
        session.user.emailVerified = token.emailVerified as Date | null
      }

      return session
    },
    async redirect({ url, baseUrl }) {
      // Allows relative callback URLs
      if (url.startsWith('/')) return `${baseUrl}${url}`
      // Allows callback URLs on the same origin
      else if (new URL(url).origin === baseUrl) return url
      return baseUrl
    },
  },
  events: {
    async signIn({ user, account, isNewUser }) {
      // Log successful sign-ins
      console.log(`User ${user.email} signed in with ${account?.provider}`)
      
      // Send welcome email for new users
      if (isNewUser && user.email) {
        // TODO: Send welcome email
        console.log(`Welcome email queued for ${user.email}`)
      }
    },
    async signOut({ token }) {
      // Log sign-outs
      console.log(`User ${token?.email} signed out`)
    },
  },
  debug: process.env.NODE_ENV === 'development',
}

// Extend NextAuth types
declare module 'next-auth' {
  interface User {
    role: string
  }

  interface Session {
    user: {
      id: string
      name: string
      email: string
      image?: string
      role: string
      emailVerified: Date | null
    }
  }
}

declare module 'next-auth/jwt' {
  interface JWT {
    role: string
    emailVerified: Date | null
  }
}