import { User } from '@prisma/client';
import { AppError, RegisterData, LoginCredentials, ChangePasswordData, AuthResponse, UserResponse } from '@/types';
import { hashPassword, comparePassword } from '@/utils/password';
import { generateTokenPair, verifyToken } from '@/utils/jwt';
import prisma from '@/config/database';
import { logger } from '@/config/logger';

/**
 * Register a new user
 */
export async function registerUser(userData: RegisterData): Promise<AuthResponse> {
  const { name, email, password } = userData;

  // Check if user already exists
  const existingUser = await prisma.user.findUnique({
    where: { email },
  });

  if (existingUser) {
    throw new AppError('Email already registered', 409);
  }

  // Hash password
  const hashedPassword = await hashPassword(password);

  // Create user
  const user = await prisma.user.create({
    data: {
      name,
      email,
      password: hashedPassword,
      role: 'USER',
      isActive: true,
    },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      isActive: true,
      createdAt: true,
      updatedAt: true,
    },
  });

  // Generate tokens
  const { accessToken } = generateTokenPair({
    userId: user.id,
    email: user.email,
    role: user.role,
  });

  return {
    user: user as UserResponse,
    token: accessToken,
  };
}

/**
 * Login user
 */
export async function loginUser(credentials: LoginCredentials): Promise<AuthResponse> {
  const { email, password } = credentials;

  // Find user
  const user = await prisma.user.findUnique({
    where: { email },
  });

  if (!user) {
    throw new AppError('Invalid email or password', 401);
  }

  // Check if user is active
  if (!user.isActive) {
    throw new AppError('Account is disabled', 401);
  }

  // Verify password
  const isPasswordValid = await comparePassword(password, user.password);
  if (!isPasswordValid) {
    throw new AppError('Invalid email or password', 401);
  }

  // Update last login
  await prisma.user.update({
    where: { id: user.id },
    data: { lastLoginAt: new Date() },
  });

  // Generate tokens
  const { accessToken } = generateTokenPair({
    userId: user.id,
    email: user.email,
    role: user.role,
  });

  const userResponse: UserResponse = {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    isActive: user.isActive,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };

  return {
    user: userResponse,
    token: accessToken,
  };
}

/**
 * Get current user
 */
export async function getCurrentUser(userId: string): Promise<UserResponse> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      isActive: true,
      createdAt: true,
      updatedAt: true,
      lastLoginAt: true,
    },
  });

  if (!user) {
    throw new AppError('User not found', 404);
  }

  return user as UserResponse;
}

/**
 * Change user password
 */
export async function changePassword(userId: string, passwordData: ChangePasswordData): Promise<void> {
  const { currentPassword, newPassword } = passwordData;

  // Get user with password
  const user = await prisma.user.findUnique({
    where: { id: userId },
  });

  if (!user) {
    throw new AppError('User not found', 404);
  }

  // Verify current password
  const isCurrentPasswordValid = await comparePassword(currentPassword, user.password);
  if (!isCurrentPasswordValid) {
    throw new AppError('Current password is incorrect', 400);
  }

  // Hash new password
  const hashedNewPassword = await hashPassword(newPassword);

  // Update password
  await prisma.user.update({
    where: { id: userId },
    data: { 
      password: hashedNewPassword,
      passwordChangedAt: new Date(),
    },
  });
}

/**
 * Request password reset
 */
export async function requestPasswordReset(email: string): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { email },
  });

  if (!user) {
    // Don't reveal that the email doesn't exist
    logger.warn('Password reset requested for non-existent email', { email });
    return;
  }

  if (!user.isActive) {
    logger.warn('Password reset requested for inactive user', { email });
    return;
  }

  // Generate reset token (in a real app, you'd store this and send via email)
  const resetToken = generateTokenPair({
    userId: user.id,
    email: user.email,
    role: user.role,
  }).accessToken;

  // Store reset token with expiration
  await prisma.user.update({
    where: { id: user.id },
    data: {
      resetToken,
      resetTokenExpiresAt: new Date(Date.now() + 3600000), // 1 hour
    },
  });

  // TODO: Send email with reset link
  logger.info('Password reset token generated', { 
    userId: user.id, 
    email: user.email,
    token: resetToken.substring(0, 8) + '...' 
  });
}

/**
 * Reset password with token
 */
export async function resetPassword(token: string, newPassword: string): Promise<void> {
  try {
    // Verify token
    const decoded = verifyToken(token);
    
    // Find user with valid reset token
    const user = await prisma.user.findFirst({
      where: {
        id: decoded.userId,
        resetToken: token,
        resetTokenExpiresAt: {
          gte: new Date(),
        },
        isActive: true,
      },
    });

    if (!user) {
      throw new AppError('Invalid or expired reset token', 400);
    }

    // Hash new password
    const hashedPassword = await hashPassword(newPassword);

    // Update password and clear reset token
    await prisma.user.update({
      where: { id: user.id },
      data: {
        password: hashedPassword,
        resetToken: null,
        resetTokenExpiresAt: null,
        passwordChangedAt: new Date(),
      },
    });

  } catch (error) {
    if (error instanceof AppError) {
      throw error;
    }
    throw new AppError('Invalid or expired reset token', 400);
  }
}

/**
 * Refresh access token
 */
export async function refreshAccessToken(refreshToken: string): Promise<AuthResponse> {
  try {
    // Verify refresh token
    const decoded = verifyToken(refreshToken);
    
    // Find user
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: {
        id: true,
        name: true,
        email: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new AppError('User not found', 404);
    }

    if (!user.isActive) {
      throw new AppError('Account is disabled', 401);
    }

    // Generate new access token
    const { accessToken } = generateTokenPair({
      userId: user.id,
      email: user.email,
      role: user.role,
    });

    return {
      user: user as UserResponse,
      token: accessToken,
    };

  } catch (error) {
    if (error instanceof AppError) {
      throw error;
    }
    throw new AppError('Invalid refresh token', 401);
  }
}