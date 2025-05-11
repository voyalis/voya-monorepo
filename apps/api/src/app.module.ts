import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config'; // .env dosyasını okumak için

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // ConfigModule'ü tüm modüllerde kullanılabilir yap
      envFilePath: '.env', // Hangi .env dosyasını okuyacağını belirt
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule], // ConfigService'i burada da kullanabilmek için
      inject: [ConfigService], // ConfigService'i useFactory içine enjekte et
      useFactory: (configService: ConfigService) => ({
        type: 'postgres', // Veritabanı türümüz
        host: configService.get<string>('DATABASE_HOST'),
        port: parseInt(configService.get<string>('DATABASE_PORT') || '5432'), // .env'den portu oku, string ise sayıya çevir
        username: configService.get<string>('DATABASE_USER'),
        password: configService.get<string>('DATABASE_PASSWORD'),
        database: configService.get<string>('DATABASE_DB_NAME'),
        entities: [], // Şimdilik boş, ileride veritabanı tablolarımızı (entity) buraya ekleyeceğiz
        synchronize: true, // DİKKAT: Geliştirme için true, veritabanı şemasını otomatik oluşturur/günceller. ÜRETİMDE FALSE OLMALI!
        logging: true, // TypeORM'in yaptığı SQL sorgularını konsolda gösterir (geliştirme için faydalı)
      }),
    }),
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}