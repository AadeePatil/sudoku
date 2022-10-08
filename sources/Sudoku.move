module Sudoku::sudoku {
    use std::signer;
    use std::error;
    use std::vector;
    use movemate::pseudorandom;
    use aptos_framework::account::{ Self, SignerCapability };

    const SEED: vector<u8> = vector<u8>[6, 9, 4, 2, 0];
    const LENGTH: u8 = 9;
    const BLANK_BOARD: vector<vector<u8>> = vector<vector<u8>>[
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
        vector<u8>[0, 0, 0, 0, 0, 0, 0, 0, 0],
    ];

    const ESIGNER_NOT_SUDOKU: u64 = 0;
    const EPLAYER_NOT_REGISTERED: u64 = 1;
    const EPLAYER_ALREADY_REGISTERED: u64 = 2;
    const EINVALID_BOARD: u64 = 3;
    const EINVALID_SOLUTION: u64 = 4;

    struct Game has store {
        board: vector<vector<u8>>,
        creator: address,
        attempts: u64,
        completed: u64,
    }

    struct GamesHolder has key {
        games: vector<Game>,
    }

    struct GamesInfo has key {
        games_addr: address,
    }

    struct Player has key {
        current_game_id: u64,
        attempts: u64,
        completed: u64,
    }

    fun init_module(
        sender: &signer
    ) {
        assert!(
            signer::address_of(sender) == @Sudoku,
            error::permission_denied(ESIGNER_NOT_SUDOKU)
        );

        let (games_signer, _signer_cap): (signer, SignerCapability) = account::create_resource_account(sender, SEED);
        let games_addr = signer::address_of(&games_signer);

        move_to<GamesInfo>(sender, GamesInfo {
            games_addr: games_addr,
        });

        move_to<GamesHolder>(&games_signer, GamesHolder {
            games: vector::singleton<Game>(
                Game {
                    board: BLANK_BOARD,
                    creator: @Sudoku,
                    attempts: 0,
                    completed: 0,
                }
            ),
        });
    }

    public fun register(
        account: &signer
    ) {
        assert!(
            !registed(signer::address_of(account)),
            error::already_exists(EPLAYER_ALREADY_REGISTERED)
        );

        move_to(
            account,
            Player {
                current_game_id: 0,
                attempts: 0,
                completed: 0,
            }
        )
    }

    public fun add(
        creator: &signer,
        board: vector<vector<u8>>,
        solution: vector<vector<u8>>
    ) acquires GamesInfo, GamesHolder {
        let creator_addr = signer::address_of(creator);
        assert!(
            registed(creator_addr),
            error::not_found(EPLAYER_NOT_REGISTERED)
        );
        
        check_solution(&board, &solution);
        internal_add(creator_addr, board);
    }

    public fun solve(
        player: &signer,
        solution: vector<vector<u8>>
    ) acquires Player, GamesInfo, GamesHolder {
        let player_addr = signer::address_of(player);
        assert!(
            registed(player_addr),
            error::not_found(EPLAYER_NOT_REGISTERED)
        );

        internal_solve(player_addr, &solution);
    }

    public fun pass(
        player: &signer
    ) acquires Player, GamesInfo, GamesHolder {
        let player_addr = signer::address_of(player);
        assert!(
            registed(player_addr),
            error::not_found(EPLAYER_NOT_REGISTERED)
        );

        internal_pass(player_addr);
    }

    fun internal_add(
        creator: address,
        board: vector<vector<u8>>
    ) acquires GamesInfo, GamesHolder {
        let games_addr = borrow_global<GamesInfo>(@Sudoku).games_addr;
        let games = &mut borrow_global_mut<GamesHolder>(games_addr).games;

        vector::push_back<Game>(
            games,
            Game {
                board: board,
                creator: creator,
                attempts: 0,
                completed: 0,
            }
        );
    }

    fun internal_solve(
        player_addr: address,
        solution: &vector<vector<u8>>
    ) acquires Player, GamesInfo, GamesHolder {
        let player = borrow_global_mut<Player>(player_addr);
        let games_addr = borrow_global<GamesInfo>(@Sudoku).games_addr;
        let games = &mut borrow_global_mut<GamesHolder>(games_addr).games;
        let game = vector::borrow_mut<Game>(
            games,
            player.current_game_id
        );
        let board = &game.board;

        check_solution(board, solution);
        post_solution_check(player, game);
        new_game(player, games);
    }

    fun internal_pass(
        player_addr: address
    ) acquires Player, GamesInfo, GamesHolder {
        let player = borrow_global_mut<Player>(player_addr);
        let games_addr = borrow_global<GamesInfo>(@Sudoku).games_addr;
        let games = &mut borrow_global_mut<GamesHolder>(games_addr).games;

        new_game(player, games);
    }

    fun check_solution(
        board: &vector<vector<u8>>,
        solution: &vector<vector<u8>>
    ) {
        check_boards_validity(board, solution);
        check_rows(solution);
        check_cols(solution);
        check_sub_squares(solution);
    }

    fun check_boards_validity(
        board: &vector<vector<u8>>,
        solution: &vector<vector<u8>>
    ) {
        assert!(
            vector::length<vector<u8>>(board) == (LENGTH as u64),
            error::invalid_argument(EINVALID_BOARD)
        );
        assert!(
            vector::length<vector<u8>>(solution) == (LENGTH as u64),
            error::invalid_argument(EINVALID_BOARD)
        );

        let row = 0;
        let col = 0;
        while (row < vector::length<vector<u8>>(board)) {
            let board_row = vector::borrow<vector<u8>>(board, row); 
            let solution_row = vector::borrow<vector<u8>>(solution, row);
            assert!(
                vector::length<u8>(board_row) == (LENGTH as u64),
                error::invalid_argument(EINVALID_BOARD)
            );
            assert!(
                vector::length<u8>(solution_row) == (LENGTH as u64),
                error::invalid_argument(EINVALID_BOARD)
            );
            while (col < vector::length<u8>(board_row)) {
                let board_cell = *vector::borrow<u8>(board_row, col);
                let solution_cell = *vector::borrow<u8>(solution_row, col);
                assert!(
                    board_cell == solution_cell || board_cell == 0,
                    error::invalid_argument(EINVALID_BOARD)
                );
                col = col + 1;
            };
            row = row + 1;
        };
    }

    fun check_rows(
        solution: &vector<vector<u8>>
    ) {
        let row = 0;
        while (row < (LENGTH as u64)) {
            check_values(vector::borrow<vector<u8>>(solution, row));
            row = row + 1;
        };
    }

    fun check_cols(
        solution: &vector<vector<u8>>
    ) {
        let col = 0;
        let row = 0;

        while (col < (LENGTH as u64)) {
            let col_vec = vector::empty<u8>();
            while (row < (LENGTH as u64)) {
                vector::push_back<u8>(
                    &mut col_vec,
                    *vector::borrow<u8>(
                        vector::borrow<vector<u8>>(
                            solution,
                            row
                        ),
                        col
                    )
                );
                row = row + 1;
            };
            check_values(&col_vec);
            col = col + 1;
        };
    }
    
    fun check_sub_squares(
        solution: &vector<vector<u8>>
    ) {
        let row = 0;
        let col = 0;
        let sub_row = 0;
        let sub_col = 0;

        while (row < (LENGTH as u64)) {
            while (col < (LENGTH as u64)) {
                let sub_square_vec = vector::empty<u8>();
                while (sub_row < 3) {
                    while (sub_col < 3) {
                        vector::push_back(
                            &mut sub_square_vec,
                            *vector::borrow<u8>(
                                vector::borrow<vector<u8>>(
                                    solution,
                                    col + sub_col
                                ),
                                row + sub_row
                            )
                        );
                        sub_col = sub_col + 1;
                    };
                    sub_row = sub_row + 1;
                };
                check_values(&sub_square_vec);
                col = col + 3;
            };
            row = row + 3;
        };
    }

    fun check_values(
        values: &vector<u8>
    ) {
        let i: u8 = 1;
        while (i <= LENGTH) {
            assert!(
                vector::contains<u8>(values, &i),
                error::invalid_argument(EINVALID_SOLUTION)
            );
            i = i + 1;
        };
    }

    fun post_solution_check(
        player: &mut Player,
        game: &mut Game
    ) {
        player.completed =  player.completed + 1;
        game.completed = game.completed + 1;
    }

    fun new_game(
        player: &mut Player,
        games: &mut vector<Game>
    ) {
        let game_id = pseudorandom::rand_u64_range_no_sender(
            1,
            vector::length<Game>(games)
        );
        let game = vector::borrow_mut<Game>(games, game_id);
        game.attempts = game.attempts + 1;
        
        player.current_game_id = game_id;
        player.attempts = player.attempts + 1;
    }

    fun registed(
        account_addr: address
    ): bool {
        exists<Player>(account_addr)
    }

    //////////////////////////////
    // TESTS
    //////////////////////////////
     
    #[test_only]
    fun setup(
        sudoku: &signer,
        creator: &signer
    ): vector<vector<u8>> {
        init_module(sudoku);

        let board: vector<vector<u8>> = vector<vector<u8>>[
            vector<u8>[0, 0, 0, 0, 0, 0, 2, 0, 0],
            vector<u8>[0, 8, 0, 0, 0, 7, 0, 9, 0],
            vector<u8>[6, 0, 2, 0, 0, 0, 5, 0, 0],
            vector<u8>[0, 7, 0, 0, 6, 0, 0, 0, 0],
            vector<u8>[0, 0, 0, 9, 0, 1, 0, 0, 0],
            vector<u8>[0, 0, 0, 0, 2, 0, 0, 4, 0],
            vector<u8>[0, 0, 5, 0, 0, 0, 6, 0, 3],
            vector<u8>[0, 9, 0, 4, 0, 0, 0, 7, 0],
            vector<u8>[0, 0, 6, 0, 0, 0, 0, 0, 0],
        ];
        let solution: vector<vector<u8>> = vector<vector<u8>>[
            vector<u8>[9, 5, 7, 6, 1, 3, 2, 8, 4],
            vector<u8>[4, 8, 3, 2, 5, 7, 1, 9, 6],
            vector<u8>[6, 1, 2, 8, 4, 9, 5, 3, 7],
            vector<u8>[1, 7, 8, 3, 6, 4, 9, 5, 2],
            vector<u8>[5, 2, 4, 9, 7, 1, 3, 6, 8],
            vector<u8>[3, 6, 9, 5, 2, 8, 7, 4, 1],
            vector<u8>[8, 4, 5, 7, 9, 2, 6, 1, 3],
            vector<u8>[2, 9, 1, 4, 3, 6, 8, 7, 5],
            vector<u8>[7, 3, 6, 1, 8, 5, 4, 2, 9],
        ];

        register(creator);
        add(creator, board, solution);

        solution
    }
}
