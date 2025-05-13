// voya-monorepo/apps/api/data-source.ts
import 'reflect-metadata';
import { DataSource, DataSourceOptions } from 'typeorm';
import { config as dotenvConfig } from 'dotenv';
import * as path from 'path';
import { Message } from './src/messages/message.entity';
// GELECEKTEKİ TÜM ENTITY'LERİNİZİ BURAYA IMPORT EDECEKSİNİZ
// import { User } from './src/users/user.entity';
// ... vb.

dotenvConfig({ path: path.resolve(__dirname, '.env') });

export const AppDataSourceOptions: DataSourceOptions = {
  type: 'postgres',
  url: process.env.DATABASE_URL, // Fly.io ve CI için öncelikli
  host: process.env.DATABASE_URL
    ? undefined
    : process.env.DATABASE_HOST || 'localhost',
  port: process.env.DATABASE_URL
    ? undefined
    : parseInt(process.env.DATABASE_PORT || '5433', 10),
  username: process.env.DATABASE_URL ? undefined : process.env.DATABASE_USER,
  password: process.env.DATABASE_URL
    ? undefined
    : process.env.DATABASE_PASSWORD,
  database: process.env.DATABASE_URL ? undefined : process.env.DATABASE_DB_NAME,

  synchronize: false, // Üretim ve migration tabanlı geliştirme için KESİNLİKLE false!
  logging: ['query', 'error'], // Geliştirme sırasında faydalı

  entities: [
    Message, // Örnek entity
    // Buraya projenizdeki TÜM TypeORM entity sınıflarını eklemelisiniz.
    // User, Booking, Vehicle, Address, Payment vb.
    // VEYA daha önce kullandığımız glob deseni de kalabilir, ancak direkt import daha nettir:
    // path.join(__dirname, 'src', '**', '*.entity.{ts,js}'),
  ],

  // MIGRATIONS AYARLARI ARTIK BURADA GEREKLİ DEĞİL,
  // ÇÜNKÜ migrate.sh script'i SQL dosyalarını doğrudan psql ile çalıştırıyor.
  // Eğer gelecekte TypeORM'in kendi migration generate/run komutlarını kullanmak isterseniz
  // bu ayarları tekrar ekleyebilirsiniz.
  // migrations: [
  //   path.join(__dirname, 'src', 'database', 'migrations', '*.{ts,js,sql}'),
  // ],
  // cli: {
  //   migrationsDir: 'src/database/migrations',
  // },

  ssl: process.env.DATABASE_URL?.includes('sslmode=require')
    ? { rejectUnauthorized: false } // Neon için
    : undefined,
};

// Bu DataSource instance'ı hala NestJS uygulamasının TypeOrmModule'ü tarafından
// dolaylı olarak kullanılabilir veya bazı CLI araçları için gerekebilir.
// Ancak ana migration çalıştırma mekanizmamız artık bu dosyaya doğrudan bağlı değil.
export const AppDataSource = new DataSource(AppDataSourceOptions);
