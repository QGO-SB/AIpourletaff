import "./globals.css";

export const metadata = {
  title: "Portail IA",
  description: "Choisis ton IA et ouvre une session dessus",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
