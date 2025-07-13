# React + Vite テンプレート設定
{
  name = "react-vite";
  displayName = "React + Vite";
  description = "Modern React development with Vite bundler";
  
  framework = "react";
  bundler = "vite";
  typescript = true;
  
  dependencies = [
    "react"
    "react-dom"
  ];
  
  devDependencies = [
    "vite"
    "@vitejs/plugin-react"
    "@types/react"
    "@types/react-dom"
    "eslint-plugin-react"
    "eslint-plugin-react-hooks"
    "eslint-plugin-jsx-a11y"
  ];
  
  scripts = {
    dev = "vite";
    build = "vite build";
    preview = "vite preview";
    lint = "eslint . --ext js,jsx,ts,tsx";
    "lint:fix" = "eslint . --ext js,jsx,ts,tsx --fix";
  };
  
  files = [
    "vite.config.ts"
    "index.html"
    "src/main.tsx"
    "src/App.tsx"
    "src/App.css"
    "src/index.css"
  ];
}