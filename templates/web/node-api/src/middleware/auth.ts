import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '@/utils/jwt';
import { AppError } from '@/types';
import { logger } from '@/config/logger';
import prisma from '@/config/database';

// Extend Request interface to include user
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
        role?: string;
      };
    }
  }
}

/**
 * Middleware to authenticate requests using JWT tokens
 */
export const authenticate = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader) {
      throw new AppError('Access token is required', 401);
    }

    const token = authHeader.split(' ')[1];
    
    if (!token) {
      throw new AppError('Access token is required', 401);
    }

    // Verify and decode token
    const decoded = verifyToken(token);
    
    if (!decoded || typeof decoded === 'string') {
      throw new AppError('Invalid access token', 401);
    }

    // Check if user still exists
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: {
        id: true,
        email: true,
        role: true,
        isActive: true,
      },
    });

    if (!user) {
      throw new AppError('User no longer exists', 401);
    }

    if (!user.isActive) {
      throw new AppError('User account is disabled', 401);
    }

    // Add user to request object
    req.user = {
      id: user.id,
      email: user.email,
      role: user.role,
    };

    next();
  } catch (error) {
    if (error instanceof AppError) {
      next(error);
    } else {
      logger.error('Authentication error:', error);
      next(new AppError('Authentication failed', 401));
    }
  }
};

/**
 * Middleware to authorize requests based on user roles
 */
export const authorize = (...allowedRoles: string[]) => {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      if (!req.user) {
        throw new AppError('Authentication required', 401);
      }

      const userRole = req.user.role || 'USER';
      
      if (!allowedRoles.includes(userRole)) {
        throw new AppError('Insufficient permissions', 403);
      }

      next();
    } catch (error) {
      next(error);
    }
  };
};

/**
 * Middleware for optional authentication (user can be logged in or not)
 */
export const optionalAuth = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader) {
      return next();
    }

    const token = authHeader.split(' ')[1];
    
    if (!token) {
      return next();
    }

    // Verify and decode token
    const decoded = verifyToken(token);
    
    if (decoded && typeof decoded !== 'string') {
      // Check if user exists
      const user = await prisma.user.findUnique({
        where: { id: decoded.userId },
        select: {
          id: true,
          email: true,
          role: true,
          isActive: true,
        },
      });

      if (user && user.isActive) {
        req.user = {
          id: user.id,
          email: user.email,
          role: user.role,
        };
      }
    }

    next();
  } catch (error) {
    // Continue without authentication if token is invalid
    logger.debug('Optional auth failed, continuing without user:', error);
    next();
  }
};

/**
 * Middleware to check if user owns the resource or is admin
 */
export const ownershipOrAdmin = (resourceUserIdParam: string = 'userId') => {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      if (!req.user) {
        throw new AppError('Authentication required', 401);
      }

      const resourceUserId = req.params[resourceUserIdParam];
      const currentUserId = req.user.id;
      const userRole = req.user.role || 'USER';

      // Admin can access everything
      if (userRole === 'ADMIN') {
        return next();
      }

      // User can only access their own resources
      if (resourceUserId === currentUserId) {
        return next();
      }

      throw new AppError('Access denied to this resource', 403);
    } catch (error) {
      next(error);
    }
  };
};