import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config'; // Ortam değişkenleri için
import { Message } from './messages/message.entity'; // Oluşturduğumuz Mesaj tablosu
import { MessagesModule } from './messages/messages.module'; // Mesajlar için modülümüz

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // ConfigModule'ü tüm modüllerde kullanılabilir yap
      envFilePath: '.env', // Lokal geliştirme için .env dosyasını oku
      // Fly.io'da NODE_ENV=production olduğunda bu dosya okunmayacak,
      // bunun yerine Fly.io'ya set ettiğimiz ortam değişkenleri (secret'lar) kullanılacak.
      ignoreEnvFile: process.env.NODE_ENV === 'production',
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule], // ConfigService'i burada kullanabilmek için
      inject: [ConfigService], // ConfigService'i useFactory içine enjekte et
      useFactory: (configService: ConfigService) => {
        const dbUrl = configService.get<string>('DATABASE_URL'); // Fly.io SECRET'INDAN GELEN DEĞER

        if (dbUrl) {
          // Eğer DATABASE_URL varsa (Fly.io ortamında olacak)
          console.log(
            'Connecting to database using DATABASE_URL from environment...',
          );
          return {
            type: 'postgres',
            url: dbUrl, // Neon bağlantı dizesini doğrudan kullan
            entities: [Message], // Hangi tablolarla çalışacağımızı belirtiyoruz
            synchronize: process.env.NODE_ENV !== 'production', // DİKKAT: Sadece dev/test'te true, ÜRETİMDE KESİNLİKLE FALSE!
            logging: true, // SQL sorgularını konsolda gösterir (geliştirme/debug için faydalı)
            ssl: dbUrl.includes('sslmode=require')
              ? { rejectUnauthorized: false }
              : false, // Neon için SSL ayarı
          };
        } else {
          // Eğer DATABASE_URL yoksa (lokal geliştirme ortamı gibi), .env dosyasındaki bireysel parametreleri kullan
          console.warn(
            'DATABASE_URL not found, using individual DB parameters from .env for local development...',
          );
          return {
            type: 'postgres',
            host: configService.get<string>('DATABASE_HOST'),
            port: parseInt(
              configService.get<string>('DATABASE_PORT') || '5433',
            ),
            username: configService.get<string>('DATABASE_USER'),
            password: configService.get<string>('DATABASE_PASSWORD'),
            database: configService.get<string>('DATABASE_DB_NAME'),
            entities: [Message],
            synchronize: true, // Lokal geliştirme için true olabilir
            logging: true,
            ssl: false, // Lokal PostgreSQL genellikle SSL kullanmaz
          };
        }
      },
    }),
    MessagesModule, // Mesajlarla ilgili modülümüzü uygulamaya dahil ediyoruz
  ],
  controllers: [AppController], // Ana controller (varsayılan "Hello World!")
  providers: [AppService], // Ana servis (varsayılan "Hello World!")
})
export class AppModule {}
