import { User, Prisma } from '@prisma/client';
import { AppError, CreateUserData, UpdateUserData, UserResponse, PaginationParams, UserSearchParams, PaginatedResult } from '@/types';
import { hashPassword } from '@/utils/password';
import prisma from '@/config/database';
import { logger } from '@/config/logger';

/**
 * Get all users with pagination and search
 */
export async function getAllUsers(
  paginationParams: PaginationParams,
  searchParams: UserSearchParams
): Promise<PaginatedResult<UserResponse>> {
  const { page, limit, sortBy = 'createdAt', sortOrder = 'desc' } = paginationParams;
  const { search, role, isActive } = searchParams;

  const skip = (page - 1) * limit;

  // Build where clause
  const where: Prisma.UserWhereInput = {};

  if (search) {
    where.OR = [
      { name: { contains: search, mode: 'insensitive' } },
      { email: { contains: search, mode: 'insensitive' } },
    ];
  }

  if (role) {
    where.role = role;
  }

  if (typeof isActive === 'boolean') {
    where.isActive = isActive;
  }

  // Build order by clause
  const orderBy: Prisma.UserOrderByWithRelationInput = {
    [sortBy]: sortOrder,
  };

  // Execute queries
  const [users, total] = await Promise.all([
    prisma.user.findMany({
      where,
      skip,
      take: limit,
      orderBy,
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
    }),
    prisma.user.count({ where }),
  ]);

  const totalPages = Math.ceil(total / limit);

  return {
    data: users as UserResponse[],
    meta: {
      page,
      limit,
      total,
      totalPages,
    },
  };
}

/**
 * Get user by ID
 */
export async function getUserById(id: string): Promise<UserResponse | null> {
  const user = await prisma.user.findUnique({
    where: { id },
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

  return user as UserResponse | null;
}

/**
 * Create new user
 */
export async function createUser(userData: CreateUserData): Promise<UserResponse> {
  const { name, email, password, role = 'USER' } = userData;

  // Check if user already exists
  const existingUser = await prisma.user.findUnique({
    where: { email },
  });

  if (existingUser) {
    throw new AppError('Email already exists', 409);
  }

  // Hash password
  const hashedPassword = await hashPassword(password);

  // Create user
  const user = await prisma.user.create({
    data: {
      name,
      email,
      password: hashedPassword,
      role,
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

  return user as UserResponse;
}

/**
 * Update user
 */
export async function updateUser(id: string, updateData: UpdateUserData): Promise<UserResponse> {
  // Check if user exists
  const existingUser = await prisma.user.findUnique({
    where: { id },
  });

  if (!existingUser) {
    throw new AppError('User not found', 404);
  }

  // Check email uniqueness if email is being updated
  if (updateData.email && updateData.email !== existingUser.email) {
    const emailExists = await prisma.user.findUnique({
      where: { email: updateData.email },
    });

    if (emailExists) {
      throw new AppError('Email already exists', 409);
    }
  }

  // Update user
  const user = await prisma.user.update({
    where: { id },
    data: updateData,
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

  return user as UserResponse;
}

/**
 * Update user profile (limited fields)
 */
export async function updateUserProfile(id: string, profileData: Partial<Pick<User, 'name' | 'email'>>): Promise<UserResponse> {
  // Check if user exists
  const existingUser = await prisma.user.findUnique({
    where: { id },
  });

  if (!existingUser) {
    throw new AppError('User not found', 404);
  }

  // Check email uniqueness if email is being updated
  if (profileData.email && profileData.email !== existingUser.email) {
    const emailExists = await prisma.user.findUnique({
      where: { email: profileData.email },
    });

    if (emailExists) {
      throw new AppError('Email already exists', 409);
    }
  }

  // Update user profile
  const user = await prisma.user.update({
    where: { id },
    data: profileData,
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

  return user as UserResponse;
}

/**
 * Delete user
 */
export async function deleteUser(id: string): Promise<void> {
  // Check if user exists
  const existingUser = await prisma.user.findUnique({
    where: { id },
  });

  if (!existingUser) {
    throw new AppError('User not found', 404);
  }

  // Delete user
  await prisma.user.delete({
    where: { id },
  });
}

/**
 * Get user statistics
 */
export async function getUserStatistics(): Promise<{
  total: number;
  active: number;
  inactive: number;
  admins: number;
  users: number;
  recentlyRegistered: number;
}> {
  const [
    total,
    active,
    inactive,
    admins,
    users,
    recentlyRegistered,
  ] = await Promise.all([
    prisma.user.count(),
    prisma.user.count({ where: { isActive: true } }),
    prisma.user.count({ where: { isActive: false } }),
    prisma.user.count({ where: { role: 'ADMIN' } }),
    prisma.user.count({ where: { role: 'USER' } }),
    prisma.user.count({
      where: {
        createdAt: {
          gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // Last 7 days
        },
      },
    }),
  ]);

  return {
    total,
    active,
    inactive,
    admins,
    users,
    recentlyRegistered,
  };
}

/**
 * Search users by email or name
 */
export async function searchUsers(query: string, limit: number = 10): Promise<UserResponse[]> {
  const users = await prisma.user.findMany({
    where: {
      OR: [
        { name: { contains: query, mode: 'insensitive' } },
        { email: { contains: query, mode: 'insensitive' } },
      ],
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
    take: limit,
    orderBy: {
      name: 'asc',
    },
  });

  return users as UserResponse[];
}

/**
 * Get users with recent activity
 */
export async function getRecentlyActiveUsers(limit: number = 10): Promise<UserResponse[]> {
  const users = await prisma.user.findMany({
    where: {
      isActive: true,
      lastLoginAt: {
        not: null,
      },
    },
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
    orderBy: {
      lastLoginAt: 'desc',
    },
    take: limit,
  });

  return users as UserResponse[];
}

/**
 * Bulk update users
 */
export async function bulkUpdateUsers(
  userIds: string[],
  updateData: Partial<Pick<User, 'isActive' | 'role'>>
): Promise<number> {
  const result = await prisma.user.updateMany({
    where: {
      id: {
        in: userIds,
      },
    },
    data: updateData,
  });

  return result.count;
}

/**
 * Bulk delete users
 */
export async function bulkDeleteUsers(userIds: string[]): Promise<number> {
  const result = await prisma.user.deleteMany({
    where: {
      id: {
        in: userIds,
      },
    },
  });

  return result.count;
}