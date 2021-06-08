// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#include "ujsonin.h"
#include<stdio.h>
#include<stdlib.h>
#include<string.h>

int main( int argc, char *argv[] ) {
    ujsonin_init();
    
    if( argc == 1 ) {
        printf("Usage");
        exit(0);
    }
    string_tree *args = string_tree__new();
    char *cmd = argv[1];
    for( int i=2;i<argc;i++ ) {
        char *key = argv[i];
        if( key[0] == '-' ) {
            key++;
            char *val = argv[++i];
            char extra = 0;
            char *vals[7] = {0,0,0,0,0,0,0};
            for( int j=i+1;j<argc;j++ ) {
                char *another = argv[j];
                if( another[0] == '-' ) break;
                extra++;
                vals[extra] = another;
            }
            if( extra ) {
                vals[0] = val;
                string_tree__store_len( args, key, strlen( key ), (void *) vals, 2 );
                i += extra;
            }
            else {
                string_tree__store_len( args, key, strlen( key ), (void *) val, 1 );
            }
        }
    }
    
    char type;
    if( !strncmp(cmd,"makefile",8) ) {
        char *file = string_tree__get_len( args, "file", 4, &type );
        char *defaults = string_tree__get_len( args, "defaults", 8, &type );
        char *prefix1 = string_tree__get_len( args, "prefix", 6, &type );
        
        char prefix[100];
        if( prefix1 ) sprintf(prefix,"%s_",prefix1);
        char *d1, *d2;
        node_hash__dump_to_makefile( parse_with_default(file,defaults, &d1, &d2 ), prefix1 ? prefix : 0 );
        exit(0);
    }
    if( !strncmp(cmd,"get",3) ) {
        char *file = string_tree__get_len( args, "file", 4, &type );
        if( !file ) {
            fprintf(stderr,"-file must be specified\n");
            exit(1);
        }
        char *defaults = string_tree__get_len( args, "defaults", 8, &type );
        char *d1,*d2;
        jnode *cur = (jnode *) parse_with_default( file, defaults, &d1, &d2 );
        
        void *pathV = string_tree__get_len( args, "path", 4, &type );
        if( !pathV ) {
            fprintf(stderr,"-path must be specified\n");
            exit(1);
        }
        char *onepart[2] = {0,0};
        char **parts;
        if( type == 1 ) {
            onepart[0] = (char *) pathV;
            parts = onepart;
        }
        if( type == 2 ) parts = ( char ** ) pathV;
        
        for( int i=0;i<6;i++ ) {
            char *part = parts[i];
            if( !part ) break;
            node_hash *curhash = ( node_hash * ) cur;
            cur = node_hash__get( curhash, part, strlen( part ) );
        }
        jnode__dump_env( cur );
        exit(0);
    }
    if( !strncmp(cmd,"test",4) ) {
        int len;
        char *data = slurp_file( "test.json", &len );
        int err;
        node_hash *root = parse( data, len, NULL, &err );
        jnode__dump( (jnode *) root, 0 );
        node_hash__delete( root );
        exit(0);   
    }
    fprintf(stderr,"Unknown command '%s'\n", cmd );
    return 1;
}