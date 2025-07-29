import { z } from 'zod'
import bcrypt from 'bcryptjs'
import { TRPCError } from '@trpc/server'

import { createTRPCRouter, publicProcedure, protectedProcedure } from '@/server/api/trpc'

export const authRouter = createTRPCRouter({
  register: publicProcedure
    .input(
      z.object({
        name: z.string().min(2, 'Name must be at least 2 characters'),
        email: z.string().email('Invalid email address'),
        password: z
          .string()
          .min(8, 'Password must be at least 8 characters')
          .regex(
            /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
            'Password must contain at least one uppercase letter, one lowercase letter, and one number'
          ),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { name, email, password } = input

      // Check if user already exists
      const existingUser = await ctx.prisma.user.findUnique({
        where: { email },
      })

      if (existingUser) {
        throw new TRPCError({
          code: 'CONFLICT',
          message: 'User with this email already exists',
        })
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 12)

      // Create user
      const user = await ctx.prisma.user.create({
        data: {
          name,
          email,
          password: hashedPassword,
        },
        select: {
          id: true,
          name: true,
          email: true,
          createdAt: true,
        },
      })

      return {
        user,
        message: 'User created successfully',
      }
    }),

  login: publicProcedure
    .input(
      z.object({
        email: z.string().email('Invalid email address'),
        password: z.string().min(1, 'Password is required'),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { email, password } = input

      // Find user
      const user = await ctx.prisma.user.findUnique({
        where: { email },
      })

      if (!user || !user.password) {
        throw new TRPCError({
          code: 'UNAUTHORIZED',
          message: 'Invalid email or password',
        })
      }

      // Check password
      const isValidPassword = await bcrypt.compare(password, user.password)

      if (!isValidPassword) {
        throw new TRPCError({
          code: 'UNAUTHORIZED',
          message: 'Invalid email or password',
        })
      }

      // Update last login
      await ctx.prisma.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date() },
      })

      return {
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role,
        },
        message: 'Login successful',
      }
    }),

  changePassword: protectedProcedure
    .input(
      z.object({
        currentPassword: z.string().min(1, 'Current password is required'),
        newPassword: z
          .string()
          .min(8, 'Password must be at least 8 characters')
          .regex(
            /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
            'Password must contain at least one uppercase letter, one lowercase letter, and one number'
          ),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { currentPassword, newPassword } = input
      const userId = ctx.session.user.id

      // Get user with password
      const user = await ctx.prisma.user.findUnique({
        where: { id: userId },
      })

      if (!user || !user.password) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'User not found',
        })
      }

      // Verify current password
      const isValidPassword = await bcrypt.compare(currentPassword, user.password)

      if (!isValidPassword) {
        throw new TRPCError({
          code: 'UNAUTHORIZED',
          message: 'Current password is incorrect',
        })
      }

      // Hash new password
      const hashedNewPassword = await bcrypt.hash(newPassword, 12)

      // Update password
      await ctx.prisma.user.update({
        where: { id: userId },
        data: { password: hashedNewPassword },
      })

      return {
        message: 'Password changed successfully',
      }
    }),

  requestPasswordReset: publicProcedure
    .input(
      z.object({
        email: z.string().email('Invalid email address'),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { email } = input

      // Check if user exists
      const user = await ctx.prisma.user.findUnique({
        where: { email },
      })

      if (!user) {
        // Don't reveal if user exists or not for security
        return {
          message: 'If a user with that email exists, a password reset link has been sent.',
        }
      }

      // Generate reset token (in a real app, you'd save this to the database and send an email)
      const resetToken = crypto.randomUUID()
      const resetTokenExpiry = new Date(Date.now() + 3600000) // 1 hour

      // Save reset token to database
      await ctx.prisma.verificationToken.create({
        data: {
          identifier: email,
          token: resetToken,
          expires: resetTokenExpiry,
        },
      })

      // In a real app, you'd send an email here
      // await sendPasswordResetEmail(email, resetToken)

      return {
        message: 'If a user with that email exists, a password reset link has been sent.',
      }
    }),

  resetPassword: publicProcedure
    .input(
      z.object({
        token: z.string().min(1, 'Reset token is required'),
        newPassword: z
          .string()
          .min(8, 'Password must be at least 8 characters')
          .regex(
            /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
            'Password must contain at least one uppercase letter, one lowercase letter, and one number'
          ),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { token, newPassword } = input

      // Find and validate reset token
      const resetToken = await ctx.prisma.verificationToken.findUnique({
        where: { token },
      })

      if (!resetToken || resetToken.expires < new Date()) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'Invalid or expired reset token',
        })
      }

      // Find user by email
      const user = await ctx.prisma.user.findUnique({
        where: { email: resetToken.identifier },
      })

      if (!user) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'User not found',
        })
      }

      // Hash new password
      const hashedPassword = await bcrypt.hash(newPassword, 12)

      // Update password and delete reset token
      await ctx.prisma.$transaction([
        ctx.prisma.user.update({
          where: { id: user.id },
          data: { password: hashedPassword },
        }),
        ctx.prisma.verificationToken.delete({
          where: { token },
        }),
      ])

      return {
        message: 'Password reset successfully',
      }
    }),

  deleteAccount: protectedProcedure
    .input(
      z.object({
        password: z.string().min(1, 'Password is required'),
        confirmation: z.literal('DELETE', {
          errorMap: () => ({ message: 'You must type DELETE to confirm' }),
        }),
      })
    )
    .mutation(async ({ input, ctx }) => {
      const { password } = input
      const userId = ctx.session.user.id

      // Get user with password
      const user = await ctx.prisma.user.findUnique({
        where: { id: userId },
      })

      if (!user || !user.password) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'User not found',
        })
      }

      // Verify password
      const isValidPassword = await bcrypt.compare(password, user.password)

      if (!isValidPassword) {
        throw new TRPCError({
          code: 'UNAUTHORIZED',
          message: 'Incorrect password',
        })
      }

      // Soft delete user (mark as deleted)
      await ctx.prisma.user.update({
        where: { id: userId },
        data: {
          deletedAt: new Date(),
          email: `deleted_${Date.now()}_${user.email}`, // Prevent email conflicts
        },
      })

      return {
        message: 'Account deleted successfully',
      }
    }),
})