export interface User {
  id: string
  name: string
  email: string
  avatar?: string
  bio?: string
  phone?: string
  dateOfBirth?: string
  location?: string
  website?: string
  role: 'user' | 'admin' | 'moderator'
  isEmailVerified: boolean
  isPhoneVerified: boolean
  preferences: UserPreferences
  createdAt: string
  updatedAt: string
  lastLoginAt?: string
}

export interface UserPreferences {
  theme: 'light' | 'dark' | 'system'
  language: string
  timezone: string
  notifications: NotificationPreferences
  privacy: PrivacyPreferences
}

export interface NotificationPreferences {
  push: boolean
  email: boolean
  sms: boolean
  marketing: boolean
  updates: boolean
  reminders: boolean
}

export interface PrivacyPreferences {
  profileVisibility: 'public' | 'friends' | 'private'
  showEmail: boolean
  showPhone: boolean
  showLocation: boolean
  allowSearchByEmail: boolean
  allowSearchByPhone: boolean
}

export interface UserStats {
  postsCount: number
  followersCount: number
  followingCount: number
  likesCount: number
}

export interface UserProfile extends User {
  stats: UserStats
  isFollowing?: boolean
  isBlocked?: boolean
}

export interface UpdateUserRequest {
  name?: string
  bio?: string
  phone?: string
  dateOfBirth?: string
  location?: string
  website?: string
  preferences?: Partial<UserPreferences>
}

export interface ChangePasswordRequest {
  currentPassword: string
  newPassword: string
  confirmPassword: string
}

export interface UserSearchResult {
  id: string
  name: string
  email: string
  avatar?: string
  bio?: string
  isFollowing?: boolean
}

export interface FollowRequest {
  id: string
  fromUser: User
  toUser: User
  status: 'pending' | 'accepted' | 'rejected'
  createdAt: string
}

export interface BlockedUser {
  id: string
  user: User
  blockedAt: string
}

export type UserRole = User['role']
export type UserTheme = UserPreferences['theme']