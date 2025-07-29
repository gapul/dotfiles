import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

export const db = globalForPrisma.prisma ?? 
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
    errorFormat: 'pretty',
  })

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = db

// Database health check
export async function checkDatabaseHealth(): Promise<boolean> {
  try {
    await db.$queryRaw`SELECT 1`
    return true
  } catch (error) {
    console.error('Database health check failed:', error)
    return false
  }
}

// Database connection
export async function connectDatabase(): Promise<void> {
  try {
    await db.$connect()
    console.log('Database connected successfully')
  } catch (error) {
    console.error('Failed to connect to database:', error)
    throw error
  }
}

// Database disconnection
export async function disconnectDatabase(): Promise<void> {
  try {
    await db.$disconnect()
    console.log('Database disconnected successfully')
  } catch (error) {
    console.error('Failed to disconnect from database:', error)
    throw error
  }
}

// Database utilities
export const dbUtils = {
  // Soft delete utility
  async softDelete<T extends { deletedAt?: Date | null }>(
    model: any,
    where: any
  ): Promise<T> {
    return model.update({
      where,
      data: { deletedAt: new Date() },
    })
  },

  // Restore soft deleted record
  async restore<T extends { deletedAt?: Date | null }>(
    model: any,
    where: any
  ): Promise<T> {
    return model.update({
      where,
      data: { deletedAt: null },
    })
  },

  // Find many excluding soft deleted
  async findManyActive<T>(
    model: any,
    args: any = {}
  ): Promise<T[]> {
    return model.findMany({
      ...args,
      where: {
        ...args.where,
        deletedAt: null,
      },
    })
  },

  // Count excluding soft deleted
  async countActive(
    model: any,
    where: any = {}
  ): Promise<number> {
    return model.count({
      where: {
        ...where,
        deletedAt: null,
      },
    })
  },

  // Transaction wrapper with retry logic
  async withTransaction<T>(
    operation: (tx: PrismaClient) => Promise<T>,
    maxRetries = 3
  ): Promise<T> {
    let lastError: Error

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await db.$transaction(operation, {
          maxWait: 5000, // 5 seconds
          timeout: 10000, // 10 seconds
        })
      } catch (error) {
        lastError = error as Error
        
        // Don't retry on certain types of errors
        if (
          error instanceof Error &&
          (error.message.includes('Unique constraint') ||
           error.message.includes('Foreign key constraint'))
        ) {
          throw error
        }

        if (attempt === maxRetries) {
          break
        }

        // Wait before retrying (exponential backoff)
        await new Promise(resolve => 
          setTimeout(resolve, Math.pow(2, attempt) * 100)
        )
      }
    }

    throw lastError!
  },

  // Pagination helper
  async paginate<T>(
    model: any,
    {
      page = 1,
      limit = 10,
      where = {},
      orderBy = {},
      include = {},
      select = {},
    }: {
      page?: number
      limit?: number
      where?: any
      orderBy?: any
      include?: any
      select?: any
    } = {}
  ): Promise<{
    data: T[]
    meta: {
      page: number
      limit: number
      total: number
      totalPages: number
      hasNextPage: boolean
      hasPrevPage: boolean
    }
  }> {
    const skip = (page - 1) * limit

    const [data, total] = await Promise.all([
      model.findMany({
        where: { ...where, deletedAt: null },
        orderBy,
        include,
        select: Object.keys(select).length > 0 ? select : undefined,
        skip,
        take: limit,
      }),
      model.count({
        where: { ...where, deletedAt: null },
      }),
    ])

    const totalPages = Math.ceil(total / limit)

    return {
      data,
      meta: {
        page,
        limit,
        total,
        totalPages,
        hasNextPage: page < totalPages,
        hasPrevPage: page > 1,
      },
    }
  },

  // Search helper
  async search<T>(
    model: any,
    {
      query,
      fields,
      page = 1,
      limit = 10,
      where = {},
      orderBy = {},
    }: {
      query: string
      fields: string[]
      page?: number
      limit?: number
      where?: any
      orderBy?: any
    }
  ): Promise<{
    data: T[]
    meta: {
      page: number
      limit: number
      total: number
      totalPages: number
      query: string
    }
  }> {
    const searchConditions = fields.map(field => ({
      [field]: {
        contains: query,
        mode: 'insensitive' as const,
      },
    }))

    const searchWhere = {
      ...where,
      deletedAt: null,
      OR: searchConditions,
    }

    return this.paginate(model, {
      page,
      limit,
      where: searchWhere,
      orderBy,
    }).then(result => ({
      ...result,
      meta: {
        ...result.meta,
        query,
      },
    }))
  },
}

export default db