import { z } from 'zod'
import { TRPCError } from '@trpc/server'

import { createTRPCRouter, protectedProcedure } from '@/server/api/trpc'

export const userRouter = createTRPCRouter({
  getProfile: protectedProcedure.query(async ({ ctx }) => {
    const userId = ctx.session.user.id

    const user = await ctx.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        name: true,
        email: true,
        image: true,
        bio: true,
        website: true,
        location: true,
        role: true,
        createdAt: true,
        lastLoginAt: true,
        _count: {
          select: {
            posts: true,
            comments: true,
            likes: true,
          },
        },
      },
    })

    if (!user) {
      throw new TRPCError({
        code: 'NOT_FOUND',
        message: 'User not found',
      })
    }

    return user
  }),

  updateProfile: protectedProcedure
    .input(
      z.object({
        name: z.string().min(2, 'Name must be at least 2 characters').optional(),
        bio: z.string().max(500, 'Bio must be less than 500 characters').optional(),
        website: z.string().url('Invalid website URL').optional().or(z.literal('')),
        location: z.string().max(100, 'Location must be less than 100 characters').optional(),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const userId = ctx.session.user.id

      const updatedUser = await ctx.prisma.user.update({
        where: { id: userId },
        data: {
          ...input,
          website: input.website === '' ? null : input.website,
        },
        select: {
          id: true,
          name: true,
          email: true,
          image: true,
          bio: true,
          website: true,
          location: true,
          updatedAt: true,
        },
      })

      return updatedUser
    }),

  updateAvatar: protectedProcedure
    .input(
      z.object({
        image: z.string().url('Invalid image URL'),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const userId = ctx.session.user.id

      const updatedUser = await ctx.prisma.user.update({
        where: { id: userId },
        data: { image: input.image },
        select: {
          id: true,
          name: true,
          image: true,
        },
      })

      return updatedUser
    }),

  getUserStats: protectedProcedure.query(async ({ ctx }) => {
    const userId = ctx.session.user.id

    const [postsCount, commentsCount, likesCount, likesReceived] = await Promise.all([
      ctx.prisma.post.count({
        where: { authorId: userId, deletedAt: null },
      }),
      ctx.prisma.comment.count({
        where: { authorId: userId, deletedAt: null },
      }),
      ctx.prisma.like.count({
        where: { userId },
      }),
      ctx.prisma.like.count({
        where: {
          post: { authorId: userId, deletedAt: null },
        },
      }),
    ])

    return {
      postsCount,
      commentsCount,
      likesGiven: likesCount,
      likesReceived,
    }
  }),

  getPublicProfile: protectedProcedure
    .input(
      z.object({
        userId: z.string().cuid('Invalid user ID'),
      })
    )
    .query(async ({ input, ctx }) => {
      const { userId } = input

      const user = await ctx.prisma.user.findUnique({
        where: { id: userId, deletedAt: null },
        select: {
          id: true,
          name: true,
          image: true,
          bio: true,
          website: true,
          location: true,
          createdAt: true,
          _count: {
            select: {
              posts: {
                where: { published: true, deletedAt: null },
              },
              comments: {
                where: { deletedAt: null },
              },
            },
          },
        },
      })

      if (!user) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'User not found',
        })
      }

      return user
    }),

  getUserPosts: protectedProcedure
    .input(
      z.object({
        userId: z.string().cuid('Invalid user ID').optional(),
        limit: z.number().min(1).max(100).default(10),
        cursor: z.string().cuid().optional(),
        published: z.boolean().default(true),
      })
    )
    .query(async ({ input, ctx }) => {
      const { userId = ctx.session.user.id, limit, cursor, published } = input

      const posts = await ctx.prisma.post.findMany({
        where: {
          authorId: userId,
          published: published ? true : undefined,
          deletedAt: null,
        },
        include: {
          author: {
            select: {
              id: true,
              name: true,
              image: true,
            },
          },
          _count: {
            select: {
              comments: {
                where: { deletedAt: null },
              },
              likes: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: limit + 1,
        cursor: cursor ? { id: cursor } : undefined,
      })

      let nextCursor: typeof cursor | undefined = undefined
      if (posts.length > limit) {
        const nextItem = posts.pop()
        nextCursor = nextItem?.id
      }

      return {
        posts,
        nextCursor,
      }
    }),

  searchUsers: protectedProcedure
    .input(
      z.object({
        query: z.string().min(1, 'Search query is required'),
        limit: z.number().min(1).max(50).default(10),
        cursor: z.string().cuid().optional(),
      })
    )
    .query(async ({ input, ctx }) => {
      const { query, limit, cursor } = input

      const users = await ctx.prisma.user.findMany({
        where: {
          deletedAt: null,
          OR: [
            { name: { contains: query, mode: 'insensitive' } },
            { email: { contains: query, mode: 'insensitive' } },
            { bio: { contains: query, mode: 'insensitive' } },
          ],
        },
        select: {
          id: true,
          name: true,
          image: true,
          bio: true,
          _count: {
            select: {
              posts: {
                where: { published: true, deletedAt: null },
              },
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: limit + 1,
        cursor: cursor ? { id: cursor } : undefined,
      })

      let nextCursor: typeof cursor | undefined = undefined
      if (users.length > limit) {
        const nextItem = users.pop()
        nextCursor = nextItem?.id
      }

      return {
        users,
        nextCursor,
      }
    }),

  getUserActivity: protectedProcedure
    .input(
      z.object({
        limit: z.number().min(1).max(50).default(20),
        cursor: z.string().cuid().optional(),
      })
    )
    .query(async ({ input, ctx }) => {
      const { limit, cursor } = input
      const userId = ctx.session.user.id

      // Get recent posts
      const recentPosts = await ctx.prisma.post.findMany({
        where: {
          authorId: userId,
          deletedAt: null,
        },
        select: {
          id: true,
          title: true,
          createdAt: true,
        },
        orderBy: { createdAt: 'desc' },
        take: 10,
      })

      // Get recent comments
      const recentComments = await ctx.prisma.comment.findMany({
        where: {
          authorId: userId,
          deletedAt: null,
        },
        include: {
          post: {
            select: {
              id: true,
              title: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: 10,
      })

      // Get recent likes
      const recentLikes = await ctx.prisma.like.findMany({
        where: { userId },
        include: {
          post: {
            select: {
              id: true,
              title: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: 10,
      })

      return {
        recentPosts,
        recentComments,
        recentLikes,
      }
    }),
})