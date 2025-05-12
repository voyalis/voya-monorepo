// voya-monorepo/apps/api/src/messages/messages.controller.ts
import {
  Controller,
  Get,
  Post,
  Body,
  ValidationPipe,
  UsePipes,
} from '@nestjs/common';
import { MessagesService, CreateMessageDto } from './messages.service';
import { Message } from './message.entity';

@Controller('messages')
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  @Post()
  @UsePipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  )
  async create(@Body() createMessageDto: CreateMessageDto): Promise<Message> {
    return this.messagesService.create(createMessageDto);
  }

  @Get()
  async findAll(): Promise<Message[]> {
    return this.messagesService.findAll();
  }
}
