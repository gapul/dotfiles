import bcrypt from 'bcryptjs';

const SALT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12', 10);

/**
 * Hash a password
 */
export async function hashPassword(password: string): Promise<string> {
  try {
    const salt = await bcrypt.genSalt(SALT_ROUNDS);
    return await bcrypt.hash(password, salt);
  } catch (error) {
    throw new Error('Failed to hash password');
  }
}

/**
 * Compare password with hash
 */
export async function comparePassword(password: string, hash: string): Promise<boolean> {
  try {
    return await bcrypt.compare(password, hash);
  } catch (error) {
    throw new Error('Failed to compare password');
  }
}

/**
 * Generate a random password
 */
export function generateRandomPassword(length: number = 12): string {
  const lowercase = 'abcdefghijklmnopqrstuvwxyz';
  const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const numbers = '0123456789';
  const symbols = '!@#$%^&*()_+-=[]{}|;:,.<>?';
  
  const allChars = lowercase + uppercase + numbers + symbols;
  
  let password = '';
  
  // Ensure at least one character from each category
  password += lowercase[Math.floor(Math.random() * lowercase.length)];
  password += uppercase[Math.floor(Math.random() * uppercase.length)];
  password += numbers[Math.floor(Math.random() * numbers.length)];
  password += symbols[Math.floor(Math.random() * symbols.length)];
  
  // Fill the rest randomly
  for (let i = password.length; i < length; i++) {
    password += allChars[Math.floor(Math.random() * allChars.length)];
  }
  
  // Shuffle the password
  return password.split('').sort(() => Math.random() - 0.5).join('');
}

/**
 * Validate password strength
 */
export interface PasswordStrength {
  isValid: boolean;
  score: number; // 0-5 (0: very weak, 5: very strong)
  feedback: string[];
}

export function validatePasswordStrength(password: string): PasswordStrength {
  const feedback: string[] = [];
  let score = 0;

  // Length check
  if (password.length < 8) {
    feedback.push('Password must be at least 8 characters long');
  } else if (password.length >= 8 && password.length < 12) {
    score += 1;
  } else if (password.length >= 12) {
    score += 2;
  }

  // Character variety checks
  const hasLowercase = /[a-z]/.test(password);
  const hasUppercase = /[A-Z]/.test(password);
  const hasNumbers = /\d/.test(password);
  const hasSymbols = /[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/.test(password);

  if (!hasLowercase) {
    feedback.push('Include lowercase letters');
  } else {
    score += 0.5;
  }

  if (!hasUppercase) {
    feedback.push('Include uppercase letters');
  } else {
    score += 0.5;
  }

  if (!hasNumbers) {
    feedback.push('Include numbers');
  } else {
    score += 0.5;
  }

  if (!hasSymbols) {
    feedback.push('Include special characters');
  } else {
    score += 0.5;
  }

  // Common patterns check
  const commonPatterns = [
    /(.)\1{2,}/, // Repeated characters
    /123456|654321|abcdef|qwerty|password/i, // Common sequences
  ];

  for (const pattern of commonPatterns) {
    if (pattern.test(password)) {
      feedback.push('Avoid common patterns and repeated characters');
      score -= 1;
      break;
    }
  }

  // Normalize score to 0-5 range
  score = Math.max(0, Math.min(5, Math.round(score)));

  const isValid = score >= 3 && feedback.length === 0;

  if (score === 0 || score === 1) {
    feedback.unshift('Very weak password');
  } else if (score === 2) {
    feedback.unshift('Weak password');
  } else if (score === 3) {
    feedback.unshift('Fair password');
  } else if (score === 4) {
    feedback.unshift('Good password');
  } else if (score === 5) {
    feedback.unshift('Strong password');
  }

  return {
    isValid,
    score,
    feedback,
  };
}