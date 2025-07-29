import { Request, Response } from 'express';
import { AppError, LoginCredentials, RegisterData, ChangePasswordData } from '@/types';
import * as authService from '@/services/authService';
import { logger } from '@/config/logger';

/**
 * Register a new user
 */
export const register = async (req: Request, res: Response): Promise<void> => {
  const userData: RegisterData = req.body;
  
  logger.info('User registration attempt', { email: userData.email });
  
  const result = await authService.registerUser(userData);
  
  logger.info('User registered successfully', { 
    userId: result.user.id, 
    email: result.user.email 
  });
  
  res.status(201).json({
    success: true,
    message: 'User registered successfully',
    data: result,
  });
};

/**
 * Login user
 */
export const login = async (req: Request, res: Response): Promise<void> => {
  const credentials: LoginCredentials = req.body;
  
  logger.info('User login attempt', { email: credentials.email });
  
  const result = await authService.loginUser(credentials);
  
  logger.info('User logged in successfully', { 
    userId: result.user.id, 
    email: result.user.email 
  });
  
  res.json({
    success: true,
    message: 'Login successful',
    data: result,
  });
};

/**
 * Logout user
 */
export const logout = async (req: Request, res: Response): Promise<void> => {
  const userId = req.user?.id;
  
  if (userId) {
    logger.info('User logout', { userId });
    // Here you could implement token blacklisting if needed
  }
  
  res.json({
    success: true,
    message: 'Logout successful',
  });
};

/**
 * Get current user profile
 */
export const getCurrentUser = async (req: Request, res: Response): Promise<void> => {
  const userId = req.user?.id;
  
  if (!userId) {
    throw new AppError('User not found in request', 401);
  }
  
  const user = await authService.getCurrentUser(userId);
  
  res.json({
    success: true,
    data: user,
  });
};

/**
 * Change user password
 */
export const changePassword = async (req: Request, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const passwordData: ChangePasswordData = req.body;
  
  if (!userId) {
    throw new AppError('User not found in request', 401);
  }
  
  logger.info('Password change attempt', { userId });
  
  await authService.changePassword(userId, passwordData);
  
  logger.info('Password changed successfully', { userId });
  
  res.json({
    success: true,
    message: 'Password changed successfully',
  });
};

/**
 * Request password reset
 */
export const forgotPassword = async (req: Request, res: Response): Promise<void> => {
  const { email } = req.body;
  
  logger.info('Password reset request', { email });
  
  await authService.requestPasswordReset(email);
  
  // Always return success to prevent email enumeration
  res.json({
    success: true,
    message: 'If the email exists, a password reset link has been sent',
  });
};

/**
 * Reset password with token
 */
export const resetPassword = async (req: Request, res: Response): Promise<void> => {
  const { token, password } = req.body;
  
  logger.info('Password reset attempt', { token: token.substring(0, 8) + '...' });
  
  await authService.resetPassword(token, password);
  
  logger.info('Password reset successful');
  
  res.json({
    success: true,
    message: 'Password reset successful',
  });
};

/**
 * Refresh access token
 */
export const refreshToken = async (req: Request, res: Response): Promise<void> => {
  const { refreshToken } = req.body;
  
  if (!refreshToken) {
    throw new AppError('Refresh token is required', 400);
  }
  
  logger.info('Token refresh attempt');
  
  const result = await authService.refreshAccessToken(refreshToken);
  
  logger.info('Token refreshed successfully', { userId: result.user.id });
  
  res.json({
    success: true,
    message: 'Token refreshed successfully',
    data: result,
  });
};