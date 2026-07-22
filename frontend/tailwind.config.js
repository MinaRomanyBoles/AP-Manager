/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        cisco: {
          navy: "#0d274d",
          blue: "#049fd9",
          cyan: "#00bceb",
          gray: "#f5f7fa",
        },
      },
    },
  },
  plugins: [],
};
