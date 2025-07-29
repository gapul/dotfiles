# {{PROJECT_NAME}}

A modern full-stack Next.js application built with TypeScript, featuring authentication, database integration, payments, and a comprehensive UI component system.

## 🚀 Features

### Core Framework
- **Next.js 14** - Latest App Router with Server Components
- **TypeScript** - Full type safety across the entire stack
- **Tailwind CSS** - Utility-first CSS framework
- **Shadcn/ui** - Beautiful and accessible React components

### Backend & Database
- **Prisma** - Next-generation ORM with type safety
- **PostgreSQL** - Robust relational database
- **tRPC** - End-to-end typesafe APIs
- **NextAuth.js** - Complete authentication solution

### Authentication
- **Multiple Providers** - Google, GitHub, Email/Password
- **Session Management** - Secure JWT-based sessions
- **Role-based Access** - User and admin roles
- **Email Verification** - Account verification workflow

### Payments & Subscriptions
- **Stripe Integration** - Complete payment processing
- **Subscription Management** - Recurring billing support
- **Webhook Handling** - Real-time payment updates
- **Price Management** - Flexible pricing models

### File Management
- **UploadThing** - Type-safe file uploads
- **Image Optimization** - Next.js Image component
- **File Storage** - Secure cloud storage

### Email & Communication
- **Resend** - Modern email delivery
- **React Email** - Beautiful email templates
- **Transactional Emails** - Automated notifications

### Developer Experience
- **Hot Reload** - Instant development feedback
- **Type Safety** - End-to-end TypeScript
- **ESLint & Prettier** - Code quality and formatting
- **Husky** - Git hooks for quality assurance

## 📋 Prerequisites

- [Node.js](https://nodejs.org/) (v18 or higher)
- [PostgreSQL](https://postgresql.org/) (v12 or higher)
- [npm](https://npmjs.com/) or [yarn](https://yarnpkg.com/)

## 🛠️ Quick Start

### 1. Environment Setup

```bash
# Copy environment variables
cp .env.example .env.local

# Edit the environment variables
nano .env.local
```

Key environment variables to configure:
```env
DATABASE_URL="postgresql://username:password@localhost:5432/{{PROJECT_NAME}}_dev"
NEXTAUTH_SECRET="your-nextauth-secret"
NEXTAUTH_URL="http://localhost:3000"
```

### 2. Database Setup

```bash
# Install dependencies
npm install

# Generate Prisma client
npm run db:generate

# Run database migrations
npm run db:migrate

# Seed the database (optional)
npm run db:seed
```

### 3. Development

```bash
# Start development server
npm run dev

# The application will be available at http://localhost:3000
```

### 4. Additional Services (Optional)

Configure these services for full functionality:

- **Google OAuth**: Get credentials from [Google Cloud Console](https://console.cloud.google.com/)
- **GitHub OAuth**: Create an app on [GitHub Developer Settings](https://github.com/settings/developers)
- **Stripe**: Get API keys from [Stripe Dashboard](https://dashboard.stripe.com/)
- **UploadThing**: Create an account at [UploadThing](https://uploadthing.com/)
- **Resend**: Get API key from [Resend](https://resend.com/)

## 📁 Project Structure

```
{{PROJECT_NAME}}/
├── app/                     # Next.js 14 App Router
│   ├── (auth)/             # Authentication pages
│   ├── (dashboard)/        # Protected dashboard pages
│   ├── api/                # API routes
│   ├── globals.css         # Global styles
│   ├── layout.tsx          # Root layout
│   └── page.tsx            # Home page
├── components/             # React components
│   ├── ui/                 # Reusable UI components
│   ├── auth/               # Authentication components
│   └── dashboard/          # Dashboard components
├── lib/                    # Utility libraries
│   ├── auth.ts             # NextAuth configuration
│   ├── db.ts               # Database connection
│   ├── trpc.ts             # tRPC configuration
│   ├── utils.ts            # Utility functions
│   └── validations.ts      # Zod schemas
├── server/                 # tRPC server
│   └── api/                # API routers
├── prisma/                 # Database schema and migrations
│   ├── schema.prisma       # Database schema
│   └── seed.ts             # Database seeding
├── emails/                 # Email templates
└── public/                 # Static assets
```

## 🔐 Authentication

The application supports multiple authentication methods:

### Email/Password Authentication
```bash
# Register a new account
POST /api/auth/signup
{
  "name": "John Doe",
  "email": "john@example.com",
  "password": "password123"
}

# Sign in
POST /api/auth/signin
{
  "email": "john@example.com",
  "password": "password123"
}
```

### OAuth Providers
- **Google**: Sign in with Google account
- **GitHub**: Sign in with GitHub account

### Session Management
- JWT-based sessions with NextAuth.js
- Automatic session refresh
- Secure cookie storage

## 💳 Payments & Subscriptions

### Stripe Integration
```typescript
// Create a subscription
const subscription = await stripe.subscriptions.create({
  customer: customerId,
  items: [{ price: priceId }],
  payment_behavior: 'default_incomplete',
  expand: ['latest_invoice.payment_intent'],
})
```

### Supported Features
- One-time payments
- Recurring subscriptions
- Multiple pricing plans
- Webhook event handling
- Customer portal access

## 📊 Database Schema

### Core Models
- **User** - User accounts and profiles
- **Account** - OAuth account linking
- **Session** - User sessions
- **Post** - Blog posts and content
- **Comment** - User comments
- **Subscription** - Payment subscriptions

### Key Relationships
- Users can have multiple OAuth accounts
- Posts belong to users and can have comments
- Users can subscribe to plans through Stripe

## 🛡️ Security

### Built-in Security Features
- **CSRF Protection** - Cross-site request forgery prevention
- **XSS Protection** - Cross-site scripting prevention
- **SQL Injection Protection** - Prisma ORM prevents SQL injection
- **Input Validation** - Zod schema validation
- **Rate Limiting** - API endpoint protection
- **Secure Headers** - Security headers configuration

### Best Practices
- Environment variables for sensitive data
- Password hashing with bcrypt
- JWT token expiration
- HTTPS enforcement in production
- Content Security Policy headers

## 🚀 Deployment

### Vercel (Recommended)
```bash
# Install Vercel CLI
npm install -g vercel

# Deploy to Vercel
vercel

# Set environment variables in Vercel dashboard
```

### Environment Variables for Production
```env
NODE_ENV=production
NEXT_PUBLIC_APP_URL=https://yourdomain.com
NEXTAUTH_URL=https://yourdomain.com
DATABASE_URL="postgresql://username:password@host:port/database"
```

### Database Migration
```bash
# Deploy database migrations
npm run db:deploy
```

## 📧 Email Templates

Email templates are built with React Email:

```typescript
// Welcome email example
import { EmailTemplate } from '@/emails/welcome'

await resend.emails.send({
  from: 'noreply@yourdomain.com',
  to: user.email,
  subject: 'Welcome to {{PROJECT_NAME}}',
  react: EmailTemplate({ name: user.name }),
})
```

## 🎨 UI Components

### Component Library
- Built with Radix UI primitives
- Fully accessible and keyboard navigable
- Customizable with Tailwind CSS
- Dark mode support

### Available Components
- Button, Input, Card, Dialog
- Toast notifications
- Form components
- Navigation components
- Data tables

## 📱 API Documentation

### tRPC Routes
```typescript
// User operations
api.user.getProfile.useQuery()
api.user.updateProfile.useMutation()

// Authentication
api.auth.register.useMutation()
api.auth.login.useMutation()

// Posts
api.post.getAll.useQuery()
api.post.create.useMutation()
```

### REST Endpoints
- `GET /api/health` - Health check
- `POST /api/auth/*` - NextAuth.js endpoints
- `POST /api/stripe/webhook` - Stripe webhooks

## 🧪 Testing

```bash
# Run type checking
npm run type-check

# Run linting
npm run lint

# Run formatting
npm run format
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make your changes and add tests
4. Run the linter: `npm run lint`
5. Run type checking: `npm run type-check`
6. Commit your changes: `git commit -am 'Add new feature'`
7. Push to the branch: `git push origin feature/new-feature`
8. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- Check the [documentation](./docs) for detailed guides
- Create an [issue](https://github.com/username/{{PROJECT_NAME}}/issues) for bug reports
- Join our [Discord](https://discord.gg/community) for community support

## 🙏 Acknowledgements

- [Next.js](https://nextjs.org/) - The React framework
- [Tailwind CSS](https://tailwindcss.com/) - Utility-first CSS framework
- [Prisma](https://prisma.io/) - Next-generation ORM
- [tRPC](https://trpc.io/) - End-to-end typesafe APIs
- [Shadcn/ui](https://ui.shadcn.com/) - Beautifully designed components
- [NextAuth.js](https://next-auth.js.org/) - Authentication for Next.js

---

Built with ❤️ using Next.js 14, TypeScript, and modern web technologies.