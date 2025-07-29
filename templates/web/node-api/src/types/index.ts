import { User } from '@prisma/client';

/**
 * Custom error class for application-specific errors
 */
export class AppError extends Error {
  public readonly statusCode: number;
  public readonly details?: unknown;

  constructor(message: string, statusCode: number = 500, details?: unknown) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
    this.name = 'AppError';

    // Maintains proper stack trace for where our error was thrown
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Standard API response interface
 */
export interface ApiResponse<T = unknown> {
  success: boolean;
  message: string;
  data?: T;
  meta?: {
    page?: number;
    limit?: number;
    total?: number;
    totalPages?: number;
  };
}

/**
 * Pagination parameters
 */
export interface PaginationParams {
  page: number;
  limit: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
}

/**
 * User-related types
 */
export type UserRole = 'USER' | 'ADMIN';

export interface CreateUserData {
  name: string;
  email: string;
  password: string;
  role?: UserRole;
}

export interface UpdateUserData {
  name?: string;
  email?: string;
  role?: UserRole;
  isActive?: boolean;
}

export interface UserResponse {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserSearchParams {
  search?: string;
  role?: UserRole;
  isActive?: boolean;
}

/**
 * Authentication-related types
 */
export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterData {
  name: string;
  email: string;
  password: string;
  confirmPassword: string;
}

export interface AuthResponse {
  user: UserResponse;
  token: string;
  refreshToken?: string;
}

export interface JwtPayload {
  userId: string;
  email: string;
  role: UserRole;
  iat?: number;
  exp?: number;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

/**
 * Password-related types
 */
export interface ChangePasswordData {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}

export interface ResetPasswordData {
  token: string;
  password: string;
  confirmPassword: string;
}

/**
 * Database query result types
 */
export interface PaginatedResult<T> {
  data: T[];
  meta: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

/**
 * File upload types
 */
export interface UploadedFile {
  fieldname: string;
  originalname: string;
  encoding: string;
  mimetype: string;
  size: number;
  destination: string;
  filename: string;
  path: string;
}

/**
 * Service response types
 */
export type ServiceResult<T> = {
  success: true;
  data: T;
} | {
  success: false;
  error: string;
  details?: unknown;
};

/**
 * Express Request extensions
 */
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
        role?: UserRole;
      };
      file?: UploadedFile;
      files?: UploadedFile[];
    }
  }
}

/**
 * Environment variables type
 */
export interface Environment {
  NODE_ENV: 'development' | 'production' | 'test';
  PORT: string;
  DATABASE_URL: string;
  JWT_SECRET: string;
  JWT_EXPIRES_IN: string;
  CORS_ORIGIN: string;
  LOG_LEVEL: string;
  API_URL: string;
  SMTP_HOST?: string;
  SMTP_PORT?: string;
  SMTP_USER?: string;
  SMTP_PASS?: string;
  FROM_EMAIL?: string;
}

/**
 * Audit trail types
 */
export interface AuditLog {
  id: string;
  userId: string;
  action: string;
  resource: string;
  resourceId: string;
  oldValues?: Record<string, unknown>;
  newValues?: Record<string, unknown>;
  ipAddress: string;
  userAgent: string;
  createdAt: Date;
}

/**
 * Health check types
 */
export interface HealthStatus {
  status: 'OK' | 'ERROR';
  timestamp: string;
  uptime: number;
  environment: string;
  version: string;
  checks: {
    database: boolean;
    memory: {
      used: number;
      free: number;
      total: number;
    };
    disk?: {
      used: number;
      free: number;
      total: number;
    };
  };
}

/**
 * Email types
 */
export interface EmailOptions {
  to: string;
  subject: string;
  text?: string;
  html?: string;
  template?: string;
  templateData?: Record<string, unknown>;
}

/**
 * Cache types
 */
export interface CacheOptions {
  key: string;
  ttl?: number; // Time to live in seconds
  tags?: string[];
}