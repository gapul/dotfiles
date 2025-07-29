import { Request, Response, NextFunction } from 'express';
import { z, ZodError, ZodSchema } from 'zod';
import { AppError } from '@/types';

/**
 * Generic validation middleware factory
 */
export const validate = (schema: {
  body?: ZodSchema;
  query?: ZodSchema;
  params?: ZodSchema;
}) => {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      // Validate request body
      if (schema.body) {
        req.body = schema.body.parse(req.body);
      }

      // Validate query parameters
      if (schema.query) {
        req.query = schema.query.parse(req.query);
      }

      // Validate route parameters
      if (schema.params) {
        req.params = schema.params.parse(req.params);
      }

      next();
    } catch (error) {
      if (error instanceof ZodError) {
        const errorMessage = error.errors.map(err => ({
          field: err.path.join('.'),
          message: err.message,
        }));
        
        next(new AppError('Validation failed', 400, errorMessage));
      } else {
        next(error);
      }
    }
  };
};

// Common validation schemas
export const commonSchemas = {
  // ID parameter validation
  idParam: z.object({
    id: z.string().uuid('Invalid ID format'),
  }),

  // Pagination query validation
  pagination: z.object({
    page: z.string().optional().transform(val => val ? parseInt(val, 10) : 1),
    limit: z.string().optional().transform(val => val ? parseInt(val, 10) : 10),
    sortBy: z.string().optional(),
    sortOrder: z.enum(['asc', 'desc']).optional().default('desc'),
  }).refine(data => data.page >= 1, {
    message: 'Page must be a positive number',
    path: ['page'],
  }).refine(data => data.limit >= 1 && data.limit <= 100, {
    message: 'Limit must be between 1 and 100',
    path: ['limit'],
  }),

  // Email validation
  email: z.string()
    .email('Invalid email format')
    .min(1, 'Email is required')
    .max(255, 'Email must be less than 255 characters'),

  // Password validation
  password: z.string()
    .min(8, 'Password must be at least 8 characters long')
    .max(128, 'Password must be less than 128 characters')
    .regex(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, 
      'Password must contain at least one lowercase letter, one uppercase letter, and one number'),

  // Name validation
  name: z.string()
    .min(1, 'Name is required')
    .max(100, 'Name must be less than 100 characters')
    .regex(/^[a-zA-Z\s'-]+$/, 'Name can only contain letters, spaces, hyphens, and apostrophes'),
};

// Authentication schemas
export const authSchemas = {
  register: z.object({
    name: commonSchemas.name,
    email: commonSchemas.email,
    password: commonSchemas.password,
    confirmPassword: z.string(),
  }).refine(data => data.password === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  }),

  login: z.object({
    email: commonSchemas.email,
    password: z.string().min(1, 'Password is required'),
  }),

  forgotPassword: z.object({
    email: commonSchemas.email,
  }),

  resetPassword: z.object({
    token: z.string().min(1, 'Reset token is required'),
    password: commonSchemas.password,
    confirmPassword: z.string(),
  }).refine(data => data.password === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  }),

  changePassword: z.object({
    currentPassword: z.string().min(1, 'Current password is required'),
    newPassword: commonSchemas.password,
    confirmPassword: z.string(),
  }).refine(data => data.newPassword === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  }),
};

// User schemas
export const userSchemas = {
  create: z.object({
    name: commonSchemas.name,
    email: commonSchemas.email,
    password: commonSchemas.password,
    role: z.enum(['USER', 'ADMIN']).optional().default('USER'),
  }),

  update: z.object({
    name: commonSchemas.name.optional(),
    email: commonSchemas.email.optional(),
    role: z.enum(['USER', 'ADMIN']).optional(),
    isActive: z.boolean().optional(),
  }).refine(data => Object.keys(data).length > 0, {
    message: 'At least one field must be provided for update',
  }),

  updateProfile: z.object({
    name: commonSchemas.name.optional(),
    email: commonSchemas.email.optional(),
  }).refine(data => Object.keys(data).length > 0, {
    message: 'At least one field must be provided for update',
  }),
};

// Search and filter schemas
export const searchSchemas = {
  userSearch: z.object({
    search: z.string().optional(),
    role: z.enum(['USER', 'ADMIN']).optional(),
    isActive: z.string().optional().transform(val => 
      val === 'true' ? true : val === 'false' ? false : undefined
    ),
  }),
};

// File upload schemas
export const fileSchemas = {
  avatar: z.object({
    mimetype: z.string().refine(
      type => ['image/jpeg', 'image/png', 'image/gif'].includes(type),
      'Only JPEG, PNG, and GIF files are allowed'
    ),
    size: z.number().max(5 * 1024 * 1024, 'File size must be less than 5MB'),
  }),
};