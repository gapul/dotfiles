# Next.js Fullstack Template Configuration
{
  name = "nextjs-fullstack";
  displayName = "Next.js Fullstack";
  description = "Full-stack Next.js application with TypeScript, Prisma, and modern tooling";
  
  type = "fullstack";
  framework = "nextjs";
  language = "typescript";
  
  features = [
    "nextjs14"       # Next.js 14 with App Router
    "typescript"     # Full TypeScript support
    "prisma"         # Database ORM
    "nextauth"       # Authentication
    "tailwindcss"    # Utility-first CSS
    "shadcn-ui"      # Modern UI components
    "trpc"           # End-to-end typesafe APIs
    "zod"            # Schema validation
    "react-hook-form" # Form management
    "tanstack-query" # Data fetching
    "uploadthing"    # File uploads
    "stripe"         # Payments (optional)
    "resend"         # Email service
    "vercel"         # Deployment optimized
  ];
  
  dependencies = [
    "next"
    "react"
    "react-dom"
    "typescript"
    "@types/react"
    "@types/react-dom"
    "@types/node"
    "prisma"
    "@prisma/client"
    "next-auth"
    "@next-auth/prisma-adapter"
    "@trpc/server"
    "@trpc/client"
    "@trpc/next"
    "@trpc/react-query"
    "@tanstack/react-query"
    "zod"
    "react-hook-form"
    "@hookform/resolvers"
    "tailwindcss"
    "postcss"
    "autoprefixer"
    "@tailwindcss/forms"
    "@tailwindcss/typography"
    "class-variance-authority"
    "clsx"
    "tailwind-merge"
    "lucide-react"
    "@radix-ui/react-slot"
    "@radix-ui/react-dialog"
    "@radix-ui/react-dropdown-menu"
    "@radix-ui/react-toast"
    "uploadthing"
    "stripe"
    "resend"
    "react-email"
    "@react-email/components"
    "date-fns"
    "nanoid"
  ];
  
  devDependencies = [
    "eslint"
    "eslint-config-next"
    "@typescript-eslint/eslint-plugin"
    "@typescript-eslint/parser"
    "prettier"
    "prettier-plugin-tailwindcss"
    "husky"
    "lint-staged"
    "@types/bcryptjs"
    "bcryptjs"
  ];
  
  scripts = {
    dev = "next dev";
    build = "next build";
    start = "next start";
    lint = "next lint";
    "lint:fix" = "next lint --fix";
    format = "prettier --write .";
    "type-check" = "tsc --noEmit";
    "db:generate" = "prisma generate";
    "db:push" = "prisma db push";
    "db:migrate" = "prisma migrate dev";
    "db:studio" = "prisma studio";
    "db:seed" = "tsx prisma/seed.ts";
    "email:dev" = "email dev";
    prepare = "husky install";
  };
  
  files = [
    "package.json"
    "next.config.js"
    "tailwind.config.ts"
    "postcss.config.js"
    "tsconfig.json"
    ".eslintrc.json"
    ".prettierrc"
    "middleware.ts"
    "app/layout.tsx"
    "app/page.tsx"
    "app/globals.css"
    "app/(auth)/sign-in/page.tsx"
    "app/(auth)/sign-up/page.tsx"
    "app/(dashboard)/dashboard/page.tsx"
    "app/api/auth/[...nextauth]/route.ts"
    "app/api/trpc/[trpc]/route.ts"
    "app/api/uploadthing/route.ts"
    "lib/auth.ts"
    "lib/db.ts"
    "lib/trpc.ts"
    "lib/utils.ts"
    "lib/validations.ts"
    "lib/uploadthing.ts"
    "components/ui/button.tsx"
    "components/ui/input.tsx"
    "components/ui/card.tsx"
    "components/ui/dialog.tsx"
    "components/ui/toast.tsx"
    "components/ui/toaster.tsx"
    "components/providers.tsx"
    "components/auth/sign-in-form.tsx"
    "components/auth/sign-up-form.tsx"
    "components/dashboard/nav.tsx"
    "server/api/root.ts"
    "server/api/routers/auth.ts"
    "server/api/routers/user.ts"
    "server/api/trpc.ts"
    "prisma/schema.prisma"
    "prisma/seed.ts"
    "emails/welcome.tsx"
    ".env.example"
    "README.md"
  ];
  
  nixPackages = [
    "nodejs_20"
    "typescript"
    "postgresql"
  ];
}