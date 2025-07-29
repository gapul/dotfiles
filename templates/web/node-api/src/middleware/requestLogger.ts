import { Request, Response, NextFunction } from 'express';
import { logger } from '@/config/logger';

/**
 * Request logging middleware
 */
export const requestLogger = (req: Request, res: Response, next: NextFunction): void => {
  const startTime = Date.now();
  
  // Skip logging for health checks in production
  if (process.env.NODE_ENV === 'production' && req.path === '/health') {
    return next();
  }

  // Log request
  logger.info('Incoming request', {
    method: req.method,
    url: req.url,
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    referer: req.get('Referer'),
    userId: req.user?.id,
  });

  // Override res.end to log response
  const originalEnd = res.end;
  res.end = function(this: Response, ...args: Parameters<typeof originalEnd>) {
    const duration = Date.now() - startTime;
    
    // Log response
    logger.info('Request completed', {
      method: req.method,
      url: req.url,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      contentLength: res.get('content-length'),
      userId: req.user?.id,
    });

    // Call original end method
    return originalEnd.apply(this, args);
  };

  next();
};