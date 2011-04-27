/* ********************************************************************************************************************
Released into the public domain, 2011 Where Labs, LLC (DangerousPrototypes.com/Ian Lesnet)

This work is free: you can redistribute it and/or modify it under the terms of Creative Commons Zero license v1.0

This work is licensed under the Creative Commons Zero 1.0 United States License. To view a copy of this license, visit http://creativecommons.org/publicdomain/zero/1.0/ or send a letter to Creative Commons, 171 Second Street, Suite 300, San Francisco, California, 94105, USA.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

Contact: http://www.DangerousPrototypes.com

Wiki: http://dangerousprototypes.com/docs/Logic_Shrimp_logic_analyzer
Forum: http://dangerousprototypes.com/forum/viewforum.php?f=58

************************************************************************************************************************** */



#include <stdio.h>
#include <stdlib.h>
#include <conio.h>
#include <unistd.h>
#include <string.h>
#include <windef.h>


#include "serial.h"


int modem =FALSE;   //set this to TRUE of testing a MODEM
int verbose = 0;

int print_usage(char * appname)
	{
		//print usage
		printf("\n\n");


        printf(" Usage:              \n");
		printf("   %s  -p port [-s speed]\n ",appname);
		printf("\n");
		printf("   Example Usage:   %s COM1  \n",appname);
		printf("\n");
		printf("           Where: -d Port is port name e.g.  COM1  \n");
		printf("                  -s Speed is port Speed  default is 115200 \n");
		printf("\n");

        printf("\n");

	    printf("-------------------------------------------------------------------------\n");


		return 0;
	}



int main(int argc, char** argv)
{
	int opt;
	char buffer[256] = {0};
//	uint8_t STCode;
	int fd;
	int res,c;
	int flag=0,firsttime=0;
	char *param_port = NULL;
	char *param_speed = NULL;
	int j,repeat_test =1;   // repeat test several times

	printf("-------------------------------------------------------------------------\n");
	printf("\n");
	printf(" Logic Shrimp Manufacturing SelfTest utility v0.2\n");
    printf(" Release Date: 04/28/2011 \n");
    printf(" License: (CC-0)\n");
	printf(" http://www.dangerousprototypes.com\n");
	printf("\n");
	printf("-------------------------------------------------------------------------\n");



	if (argc <= 1)  {

		print_usage(argv[0]);
		exit(-1);
	}

	while ((opt = getopt(argc, argv, "s:p:")) != -1) {
		switch (opt) {

			case 'p':  // device   eg. com1 com12 etc
				if ( param_port != NULL){
					printf(" Device/PORT error!\n");
					exit(-1);
				}
				param_port = strdup(optarg);
				break;
			case 's':
				if (param_speed != NULL) {
					printf(" Speed should be set: eg  115200 \n");
					exit(-1);
				}
				param_speed = strdup(optarg);

				break;

			default:
				printf(" Invalid argument %c", opt);
				print_usage(argv[0]);
				//exit(-1);
				break;
		}
	}

	 //defaults here --------------
		if (param_port==NULL){
			printf(" No serial port set\n");
			print_usage(argv[0]);
			exit(-1);
		}

		if (param_speed==NULL) {
			  param_speed=strdup("115200");
		}

		printf("\n Parameters used: Device = %s,  Speed = %s\n\n",param_port,param_speed);

		flag=0;
		//
		// Loop and repeat test as needed for manufacturing
		//

		 printf(" Press Esc to exit, any other key to start the self-test \n\n");
		while(1){
		 //pause for space, or ESC to exit
		 if (flag==1)
		 {
			printf("\n --------------- Starting a new Logic Shrimpp Self Test-------------\n");
		 }

		while(1){
			Sleep(1);
			if (flag==1){
				flag=0;   //has flag been set to just go testing?
				break;    // proceed with test
			 }
			if(kbhit()){
			   c = getch();
			   if(c == 27){
					printf("\n Esc key hit, stopping...\n");
					printf(" (Bye for now!)\n");
					exit(0);
				}else {//make space only
					printf("\n Starting test! \n");
					break;
				}
			}
		}
		//
		// Open serial port
		//
		printf(" Opening Logic Shrimp Self Test on %s at %sbps...\n", param_port, param_speed);
		fd = serial_open(param_port);
		if (fd < 0) {
			fprintf(stderr, " Error opening serial port\n");
			return -1;
		}
		serial_setup(fd,(speed_t) param_speed);
		printf(" Starting Logic Shrimp Self Test...\n");
        serial_write( fd, "\x00", 1);


		for (j=0;j<repeat_test;j++)
		{
			printf(" Test no: %i of %i \n",j+1,repeat_test);
			serial_write( fd, "\x03", 1);   // send test command
			Sleep(1);
			res= serial_read(fd, buffer, sizeof(buffer));  // get reply
			if (res >0){   //we have a replay
				/*
				printf(" Logic Shrimp Self Test Reply: ");
				printf(" ");
				for(c=0; c<res; c++){
					STCode=buffer[c];
					printf(" %02X", STCode);
				}
				printf("\n");
                */
				if (buffer[0]==0x00) {    // Test passed
				    printf("\n Logic Shrimp Self Test Reply:   %02X **PASS** :)",(uint8_t) buffer[0]);

					printf("\n\n\n The POWER and ACT led should be ON \n\n");
				}else{
					printf(" Logic Shrimp Self Test Reply:   %02X **FAIL** :(\n",(uint8_t) buffer[0]);

				}
			}else{ // if (res >0)
				printf(" Logic Shrimp Selp Test did not reply anything.. Please check connections. \n");
			}
		}
		if (firsttime==0){    // run here once and don't say again the next time
			printf(" Press any key to continue...\n");
			firsttime=1;
			while(1){
				Sleep(1);
				if(kbhit()){
					c = getch();
					break;
				}
			}
		}
		//close port so they can attach the next Bus Pirate
		serial_close(fd);
		printf("\n Connect another Logic Shrimp Board \n and press any key to start the self-test again \n");
		printf(" Or hit ESC key to stop and end the test.\n");

		while(1){
			Sleep(1);
			if(kbhit()){
				c = getch();
				if(c == 27){
					printf("\n Esc key hit, stopping...\n");
					printf(" (Bye for now!)\n");
					exit(-1);
				}else {//make space only
					flag=1;  //flag to tell the other loop to bypass another keypress
					break;
				}
			}
		}

	} // while (1)

	#define FREE(x) if(x) free(x);
	FREE(param_port);
	FREE(param_speed);
	return 0;
}  //main
