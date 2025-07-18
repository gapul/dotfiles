import { NextRequest } from 'next/server'
import NextAuth from 'next-auth'

import { authOptions } from '@/lib/auth'

const handler = (req: NextRequest) => NextAuth(req, authOptions)

export { handler as GET, handler as POST }