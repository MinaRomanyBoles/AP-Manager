import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { formatTranslation, translations, type Language, type TranslationKey } from "../i18n/translations";

interface LanguageContextValue {
  language: Language;
  setLanguage: (lang: Language) => void;
  toggleLanguage: () => void;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
  dir: "ltr" | "rtl";
}

const LanguageContext = createContext<LanguageContextValue | null>(null);

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>(() => {
    const saved = localStorage.getItem("ap-manager-language");
    return saved === "ar" ? "ar" : "en";
  });

  const setLanguage = (lang: Language) => {
    setLanguageState(lang);
    localStorage.setItem("ap-manager-language", lang);
  };

  const toggleLanguage = () => setLanguage(language === "en" ? "ar" : "en");

  const t = (key: TranslationKey, vars?: Record<string, string | number>) => {
    const text = translations[language][key] ?? translations.en[key] ?? key;
    return vars ? formatTranslation(text, vars) : text;
  };

  const dir = language === "ar" ? "rtl" : "ltr";

  useEffect(() => {
    document.documentElement.lang = language;
    document.documentElement.dir = dir;
  }, [language, dir]);

  return (
    <LanguageContext.Provider value={{ language, setLanguage, toggleLanguage, t, dir }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within LanguageProvider");
  return ctx;
}
