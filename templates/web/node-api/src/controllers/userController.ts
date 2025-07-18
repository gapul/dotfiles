import { Request, Response } from 'express';
import { AppError, CreateUserData, UpdateUserData, PaginationParams, UserSearchParams } from '@/types';
import * as userService from '@/services/userService';
import { logger } from '@/config/logger';

/**
 * Get all users with pagination and search
 */
export const getAllUsers = async (req: Request, res: Response): Promise<void> => {
  const paginationParams: PaginationParams = {
    page: Number(req.query.page) || 1,
    limit: Number(req.query.limit) || 10,
    sortBy: req.query.sortBy as string,
    sortOrder: req.query.sortOrder as 'asc' | 'desc',
  };

  const searchParams: UserSearchParams = {
    search: req.query.search as string,
    role: req.query.role as 'USER' | 'ADMIN',
    isActive: req.query.isActive as boolean,
  };

  logger.info('Fetching users', { 
    adminId: req.user?.id,
    pagination: paginationParams,
    search: searchParams 
  });

  const result = await userService.getAllUsers(paginationParams, searchParams);

  res.json({
    success: true,
    data: result.data,
    meta: result.meta,
  });
};

/**
 * Get user by ID
 */
export const getUserById = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const requesterId = req.user?.id;

  logger.info('Fetching user by ID', { userId: id, requesterId });

  const user = await userService.getUserById(id);

  if (!user) {
    throw new AppError('User not found', 404);
  }

  res.json({
    success: true,
    data: user,
  });
};

/**
 * Create new user
 */
export const createUser = async (req: Request, res: Response): Promise<void> => {
  const userData: CreateUserData = req.body;
  const adminId = req.user?.id;

  logger.info('Creating new user', { 
    email: userData.email,
    role: userData.role,
    adminId 
  });

  const user = await userService.createUser(userData);

  logger.info('User created successfully', { 
    userId: user.id,
    email: user.email,
    adminId 
  });

  res.status(201).json({
    success: true,
    message: 'User created successfully',
    data: user,
  });
};

/**
 * Update user
 */
export const updateUser = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const updateData: UpdateUserData = req.body;
  const requesterId = req.user?.id;
  const requesterRole = req.user?.role;

  logger.info('Updating user', { 
    userId: id,
    updateData: Object.keys(updateData),
    requesterId,
    requesterRole 
  });

  // Non-admin users can't update role or isActive fields
  if (requesterRole !== 'ADMIN') {
    delete updateData.role;
    delete updateData.isActive;
  }

  const user = await userService.updateUser(id, updateData);

  logger.info('User updated successfully', { 
    userId: id,
    requesterId 
  });

  res.json({
    success: true,
    message: 'User updated successfully',
    data: user,
  });
};

/**
 * Update user profile (limited fields)
 */
export const updateUserProfile = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const profileData = req.body;
  const requesterId = req.user?.id;

  // Ensure user can only update their own profile
  if (requesterId !== id && req.user?.role !== 'ADMIN') {
    throw new AppError('You can only update your own profile', 403);
  }

  logger.info('Updating user profile', { 
    userId: id,
    profileData: Object.keys(profileData),
    requesterId 
  });

  const user = await userService.updateUserProfile(id, profileData);

  logger.info('User profile updated successfully', { 
    userId: id,
    requesterId 
  });

  res.json({
    success: true,
    message: 'Profile updated successfully',
    data: user,
  });
};

/**
 * Delete user
 */
export const deleteUser = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const adminId = req.user?.id;

  // Prevent admin from deleting themselves
  if (adminId === id) {
    throw new AppError('You cannot delete your own account', 400);
  }

  logger.info('Deleting user', { userId: id, adminId });

  await userService.deleteUser(id);

  logger.info('User deleted successfully', { userId: id, adminId });

  res.json({
    success: true,
    message: 'User deleted successfully',
  });
};

/**
 * Activate user account
 */
export const activateUser = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const adminId = req.user?.id;

  logger.info('Activating user', { userId: id, adminId });

  const user = await userService.updateUser(id, { isActive: true });

  logger.info('User activated successfully', { userId: id, adminId });

  res.json({
    success: true,
    message: 'User activated successfully',
    data: user,
  });
};

/**
 * Deactivate user account
 */
export const deactivateUser = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const adminId = req.user?.id;

  // Prevent admin from deactivating themselves
  if (adminId === id) {
    throw new AppError('You cannot deactivate your own account', 400);
  }

  logger.info('Deactivating user', { userId: id, adminId });

  const user = await userService.updateUser(id, { isActive: false });

  logger.info('User deactivated successfully', { userId: id, adminId });

  res.json({
    success: true,
    message: 'User deactivated successfully',
    data: user,
  });
};