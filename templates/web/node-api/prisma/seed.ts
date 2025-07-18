import { PrismaClient, UserRole } from '@prisma/client';
import { hashPassword } from '../src/utils/password';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Starting database seeding...');

  // Clean existing data in development
  if (process.env.NODE_ENV === 'development') {
    console.log('🧹 Cleaning existing data...');
    
    await prisma.auditLog.deleteMany();
    await prisma.session.deleteMany();
    await prisma.file.deleteMany();
    await prisma.setting.deleteMany();
    await prisma.postCategory.deleteMany();
    await prisma.comment.deleteMany();
    await prisma.post.deleteMany();
    await prisma.category.deleteMany();
    await prisma.user.deleteMany();
    
    console.log('✅ Database cleaned');
  }

  // Create admin user
  console.log('👤 Creating admin user...');
  const adminPassword = await hashPassword('admin123');
  
  const adminUser = await prisma.user.create({
    data: {
      name: 'Admin User',
      email: 'admin@example.com',
      password: adminPassword,
      role: UserRole.ADMIN,
      isActive: true,
    },
  });
  
  console.log(`✅ Admin user created: ${adminUser.email}`);

  // Create regular users
  console.log('👥 Creating regular users...');
  const users = await Promise.all([
    prisma.user.create({
      data: {
        name: 'John Doe',
        email: 'john@example.com',
        password: await hashPassword('password123'),
        role: UserRole.USER,
        isActive: true,
      },
    }),
    prisma.user.create({
      data: {
        name: 'Jane Smith',
        email: 'jane@example.com',
        password: await hashPassword('password123'),
        role: UserRole.USER,
        isActive: true,
      },
    }),
    prisma.user.create({
      data: {
        name: 'Bob Wilson',
        email: 'bob@example.com',
        password: await hashPassword('password123'),
        role: UserRole.USER,
        isActive: false, // Inactive user for testing
      },
    }),
  ]);
  
  console.log(`✅ Created ${users.length} regular users`);

  // Create categories
  console.log('📂 Creating categories...');
  const categories = await Promise.all([
    prisma.category.create({
      data: {
        name: 'Technology',
        slug: 'technology',
        description: 'Tech-related posts and discussions',
      },
    }),
    prisma.category.create({
      data: {
        name: 'Programming',
        slug: 'programming',
        description: 'Programming tutorials and tips',
      },
    }),
    prisma.category.create({
      data: {
        name: 'Web Development',
        slug: 'web-development',
        description: 'Frontend and backend development',
      },
    }),
    prisma.category.create({
      data: {
        name: 'DevOps',
        slug: 'devops',
        description: 'DevOps tools and practices',
      },
    }),
  ]);
  
  console.log(`✅ Created ${categories.length} categories`);

  // Create posts
  console.log('📝 Creating posts...');
  const posts = await Promise.all([
    prisma.post.create({
      data: {
        title: 'Getting Started with TypeScript',
        content: 'TypeScript is a powerful superset of JavaScript that adds static typing...',
        published: true,
        publishedAt: new Date(),
        authorId: users[0].id,
        categories: {
          create: [
            { categoryId: categories[1].id }, // Programming
            { categoryId: categories[2].id }, // Web Development
          ],
        },
      },
    }),
    prisma.post.create({
      data: {
        title: 'Building REST APIs with Node.js',
        content: 'Learn how to build scalable REST APIs using Node.js and Express...',
        published: true,
        publishedAt: new Date(),
        authorId: users[1].id,
        categories: {
          create: [
            { categoryId: categories[1].id }, // Programming
            { categoryId: categories[2].id }, // Web Development
          ],
        },
      },
    }),
    prisma.post.create({
      data: {
        title: 'Docker Best Practices',
        content: 'Docker containerization best practices for development and production...',
        published: false, // Draft post
        authorId: adminUser.id,
        categories: {
          create: [
            { categoryId: categories[0].id }, // Technology
            { categoryId: categories[3].id }, // DevOps
          ],
        },
      },
    }),
  ]);
  
  console.log(`✅ Created ${posts.length} posts`);

  // Create comments
  console.log('💬 Creating comments...');
  const comments = await Promise.all([
    prisma.comment.create({
      data: {
        content: 'Great article! Very helpful for beginners.',
        postId: posts[0].id,
        authorId: users[1].id,
      },
    }),
    prisma.comment.create({
      data: {
        content: 'Thanks for sharing this. Could you add more examples?',
        postId: posts[0].id,
        authorId: adminUser.id,
      },
    }),
    prisma.comment.create({
      data: {
        content: 'This is exactly what I was looking for!',
        postId: posts[1].id,
        authorId: users[0].id,
      },
    }),
  ]);

  // Create a reply to the first comment
  await prisma.comment.create({
    data: {
      content: 'I agree! The examples really make it clear.',
      postId: posts[0].id,
      authorId: users[0].id,
      parentId: comments[0].id, // Reply to first comment
    },
  });
  
  console.log(`✅ Created ${comments.length + 1} comments (including 1 reply)`);

  // Create system settings
  console.log('⚙️ Creating system settings...');
  const settings = await Promise.all([
    prisma.setting.create({
      data: {
        key: 'site_name',
        value: '{{PROJECT_NAME}}',
        description: 'The name of the website',
        isPublic: true,
      },
    }),
    prisma.setting.create({
      data: {
        key: 'site_description',
        value: 'A modern TypeScript Node.js API',
        description: 'The description of the website',
        isPublic: true,
      },
    }),
    prisma.setting.create({
      data: {
        key: 'max_file_size',
        value: '10485760', // 10MB in bytes
        description: 'Maximum file upload size',
        isPublic: false,
      },
    }),
    prisma.setting.create({
      data: {
        key: 'registration_enabled',
        value: 'true',
        description: 'Whether user registration is enabled',
        isPublic: false,
      },
    }),
  ]);
  
  console.log(`✅ Created ${settings.length} system settings`);

  // Create sample audit logs
  console.log('📋 Creating audit logs...');
  await prisma.auditLog.create({
    data: {
      userId: adminUser.id,
      userEmail: adminUser.email,
      action: 'CREATE',
      resource: 'User',
      resourceId: users[0].id,
      newValues: {
        name: users[0].name,
        email: users[0].email,
        role: users[0].role,
      },
      ipAddress: '127.0.0.1',
      userAgent: 'Seed Script',
    },
  });
  
  console.log('✅ Created sample audit log');

  console.log('\n🎉 Database seeding completed successfully!');
  console.log('\n📊 Summary:');
  console.log(`   👤 Users: ${users.length + 1} (including 1 admin)`);
  console.log(`   📂 Categories: ${categories.length}`);
  console.log(`   📝 Posts: ${posts.length}`);
  console.log(`   💬 Comments: ${comments.length + 1}`);
  console.log(`   ⚙️  Settings: ${settings.length}`);
  console.log('\n🔐 Login credentials:');
  console.log('   Admin: admin@example.com / admin123');
  console.log('   User1: john@example.com / password123');
  console.log('   User2: jane@example.com / password123');
  console.log('   User3: bob@example.com / password123 (inactive)');
  console.log('\n🚀 You can now start the application!');
}

main()
  .catch((e) => {
    console.error('❌ Error during seeding:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });