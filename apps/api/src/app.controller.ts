import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller() // Eğer global prefix'iniz varsa (örn: 'api/v1'), bu ona göre ayarlanır
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get() // Bu /api/v1 (veya sadece /) endpoint'i
  getHello(): string {
    return this.appService.getHello();
  }

  @Get('health') // Bu /api/v1/health (veya sadece /health) endpoint'i olacak
  health(): { status: string; timestamp: string } {
    return { status: 'ok', timestamp: new Date().toISOString() };
  }
}
